public with sharing class DocuSignNowController{

    public string tokenURL {get; set;}
    public string nextRecipientName {get; set;}
    public string nextRecipientEmail {get; set;}
    public string nextRecipientClientUserId {get; set;}
    public Opportunity opportunity {get; set;}
    public User user {get; set;}

    private String envelopeId;
    
    private String salesforceUrl = getSFEnvironmentURL();

    private String onViewingComplete = salesforceUrl  + '/apex/DocuSignRecipientComplete?envelopeid=';
    private String onSigningComplete = salesforceUrl  + '/apex/DocuSignRecipientComplete?envelopeid=';
    
    private String onCancel = salesforceUrl  + '/apex/DocuSignNowError?errorMessage=The signer cancelled the signing session&envelopeid=';
    private String onDecline = salesforceUrl  + '/apex/DocuSignNowError?errorMessage=The signer declined to sign&envelopeid=';
    private String onSessionTimeout = salesforceUrl  + '/apex/errorMessage=The DocuSign session has timed out&DocuSignNowError?envelopeid=';
    private String onTTLExpired = salesforceUrl  + '/apex/DocuSignNowError?errorMessage=The DocuSign session has timed out&envelopeid=';

    private String onAccessCodeFailed = salesforceUrl  + '/apex/DocuSignNowError?envelopeid=';
    private String onException = salesforceUrl  + '/apex/DocuSignNowError?envelopeid=';
    private String onFaxPending = salesforceUrl  + '/apex/DocuSignNowError?envelopeid=';
    private String onIdCheckFailed = salesforceUrl  + '/apex/DocuSignNowError?envelopeid=';
    
    private PageReference errorPage = Page.DocuSignNowError;
       
    public DocuSignNowController(ApexPages.StandardController controller) {

        this.opportunity = (Opportunity)controller.getRecord();
 
        System.debug('opportunity.Id: ' + opportunity.Id);
        
        if(this.opportunity.id != null) {
            List<Opportunity> opportunities= [SELECT OwnerId FROM Opportunity where Id = :opportunity.Id];
            System.debug('ownerId : ' + opportunities.get(0).OwnerId);
            user = [SELECT Name, Email FROM User where Id = :opportunities.get(0).OwnerId];
            System.debug('user:' + user.Name + ' ' + user.Email);
        }
        tokenURL = '';

    }

    public PageReference createEnvelopeAndSignFirst() {
        System.debug('Entering createEnvelopeAndSignFirst()');
        
        System.debug('opportunity.Id: ' + opportunity.Id);
        List<Attachment> attachments = [SELECT Id, Name, Body, ContentType, BodyLength FROM Attachment where ParentId = :opportunity.Id];
        System.debug('attachments size:' + attachments.size());
        
        if(attachments.size() != 1) {
            errorPage.getParameters().put('errorMessage', 'Please verify the number of attachments on this opportunity. There should only be one attachment.');
            return errorPage;
        }
        
        Attachment attachment = attachments.get(0);
        
        DocuSignAPI.Envelope envelope = buildEnvelope(attachment);
        DocuSignAPI.ApiServiceSOAP dsApiSend = dsapi_send();
        System.debug('Calling CreateAndSendEnvelope');
                                
        try {
            DocuSignAPI.EnvelopeStatus es = dsApiSend.CreateAndSendEnvelope(envelope);
            envelopeId = es.EnvelopeID;
        } catch ( CalloutException e) {
            System.debug('Exception - ' + e );
            return errorPage;
        }
        
        DocuSignAPI.RequestRecipientTokenAuthenticationAssertion assertion = buildRequestRecipientTokenAuthenticationAssertion();

        DocuSignAPI.RequestRecipientTokenClientURLs clientURLs = buildRequestRequestRecipientTokenClientURLs(envelopeID);
        
        DocuSignAPI.Recipient recipient = envelope.Recipients.Recipient[0];

        // assumes apiService = preconfigured api proxy
        try {
            tokenURL= dsApiSend.RequestRecipientToken(envelopeId, recipient.captiveinfo.ClientUserId, recipient.UserName, recipient.Email, assertion, clientURLs);
        }  catch ( CalloutException e) {
            System.debug('Exception - ' + e );
            return errorPage;
        }

        System.debug('tokenURL: ' + tokenURL);
        PageReference pageRef = new PageReference(tokenURL);         
        return pageRef;
    }
    
    public DocuSignAPI.RequestRecipientTokenAuthenticationAssertion buildRequestRecipientTokenAuthenticationAssertion() {
    
        DocuSignAPI.RequestRecipientTokenAuthenticationAssertion assertion = new DocuSignAPI.RequestRecipientTokenAuthenticationAssertion();
        assertion.AssertionID = 'TBD';
        assertion.AuthenticationInstant = system.now();
        assertion.AuthenticationMethod = 'PaperDocuments';
        assertion.SecurityDomain = 'Salesforce.com';
        
        return assertion;
    
    }
    
    public DocuSignAPI.RequestRecipientTokenClientURLs buildRequestRequestRecipientTokenClientURLs(String envelopeID) {
    
        DocuSignAPI.RequestRecipientTokenClientURLs clientURLs = new DocuSignAPI.RequestRecipientTokenClientURLs();

        clientURLs.OnAccessCodeFailed = onAccessCodeFailed + envelopeID;
        clientURLs.OnCancel = onCancel + envelopeID;
        clientURLs.OnDecline = onDecline + envelopeID;
        clientURLs.OnException = onException + envelopeID;
        clientURLs.OnFaxPending = onFaxPending + envelopeID;
        clientURLs.OnIdCheckFailed = onIdCheckFailed + envelopeID;
        clientURLs.OnSessionTimeout = onSessionTimeout  + envelopeID;
        clientURLs.OnSigningComplete = onSigningComplete + envelopeID;
        clientURLs.OnTTLExpired = onTTLExpired + envelopeID;
        clientURLs.OnViewingComplete = onViewingComplete + envelopeID;
        
        return clientURLs;
    
    }

    
    public DocuSignAPI.Envelope buildEnvelope(Attachment attachment) {
        
        System.debug('attachment.Name:' + attachment.Name);
        System.debug('attachment.ContentType:' + attachment.ContentType);
        System.debug('attachment.BodyLength:' + attachment.BodyLength);
        
        envelopeId = '';
        string token = '';

        // create envelope info
        DocuSignAPI.Envelope envelope = new DocuSignAPI.Envelope();
        envelope.Subject = 'Please Sign your agreement';
        envelope.EmailBlurb = '';
        envelope.AccountId  = getDocuSignAccountId(); 

        DocuSignAPI.ArrayOfRecipient signers = new DocuSignAPI.ArrayOfRecipient();
        envelope.Tabs = new DocuSignAPI.ArrayOfTab();
        
        //Determine number of recipients and set up 2nd applicant with tabs if present
        if(opportunity.Applicant_2_Name__c == NULL) {
            System.debug('Found 1 Applicant');
            signers.Recipient = new DocuSignAPI.Recipient[2];
            envelope.Tabs.Tab = new DocuSignAPI.Tab[6];
        } else {
            System.debug('Found 2 Applicants');
            signers.Recipient = new DocuSignAPI.Recipient[3];
            System.debug('Setting Recipient 3 Information - Applicant 2');
            
            //2nd Applicant
            DocuSignAPI.Recipient recipient3 = new DocuSignAPI.Recipient();
            recipient3.ID = 3;
            recipient3.Type_x = 'Signer';
            recipient3.RoutingOrder = 2;
            recipient3.Email = opportunity.Applicant_2_Email__c;
            recipient3.UserName = opportunity.Applicant_2_Name__c;
            recipient3.RequireIDLookup = false;
            
            System.debug('recipient 3 UserName: ' + recipient3.UserName);
            System.debug('recipient 3 Email: ' + recipient3.Email);  
    
            // make recipient captive for embedded experience
            recipient3.CaptiveInfo = new DocuSignAPI.RecipientCaptiveInfo();
            recipient3.CaptiveInfo.ClientUserId = '3';
    
            signers.Recipient[2] = recipient3;
            
            envelope.Tabs.Tab = new DocuSignAPI.Tab[7];
            DocuSignAPI.Tab tab7 = new DocuSignAPI.Tab();
            tab7.Type_x = 'SignHere';
            tab7.RecipientID = 3;
            tab7.DocumentID = 1;
            tab7.AnchorTabItem = new DocuSignAPI.AnchorTab();
            tab7.AnchorTabItem.AnchorTabString = 's2';
            envelope.Tabs.Tab[6] = tab7;  
            
        }
        
        System.debug('Setting Recipient 1 Information - Applicant 1');
        DocuSignAPI.Recipient recipient = new DocuSignAPI.Recipient();
        recipient.ID = 1;
        recipient.Type_x = 'Signer';
        recipient.RoutingOrder = 1;
        recipient.Email = opportunity.Email__c;
        recipient.UserName = opportunity.Account.Name;
        recipient.RequireIDLookup = false;
        
        System.debug('recipient 1 UserName: ' + recipient.UserName);
        System.debug('recipient 1 Email: ' + recipient.Email);  

        // make recipient captive for embedded experience
        recipient.CaptiveInfo = new DocuSignAPI.RecipientCaptiveInfo();
        recipient.CaptiveInfo.ClientUserId = '1';

        signers.Recipient[0] = recipient;
        
        System.debug('Setting Recipient Information 2 - Admin');
        DocuSignAPI.Recipient recipient2 = new DocuSignAPI.Recipient();
        recipient2.ID = 2;
        recipient2.Type_x = 'Signer';
        recipient2.RoutingOrder = 3;
        recipient2.Email = user.Email;
        recipient2.UserName = user.Name;
        recipient2.RequireIDLookup = false;
        
        System.debug('recipient 2 UserName: ' + recipient2.UserName);
        System.debug('recipient 2 Email: ' + recipient2.Email);

        // make recipient captive for embedded experience
        recipient2.CaptiveInfo = new DocuSignAPI.RecipientCaptiveInfo();
        recipient2.CaptiveInfo.ClientUserId = '2';

        signers.Recipient[1] = recipient2;
        envelope.Recipients = signers;
        
     // Documents
        DocuSignAPI.Document document = new DocuSignAPI.Document();
        document.ID = 1;
        document.Name = attachment.Name;
        document.PDFBytes = EncodingUtil.base64Encode(attachment.body);
        document.FileExtension = 'pdf';
        envelope.Documents = new DocuSignAPI.ArrayOfDocument();
        envelope.Documents.Document = new DocuSignAPI.Document[1];
        envelope.Documents.Document[0] = document;
        
        //Tabs
        // Tab
        DocuSignAPI.Tab tab1 = new DocuSignAPI.Tab();
        tab1.Type_x = 'SignHere';
        tab1.RecipientID = 1;
        tab1.DocumentID = 1;
        tab1.AnchorTabItem = new DocuSignAPI.AnchorTab();
        tab1.AnchorTabItem.AnchorTabString = 's1';

        DocuSignAPI.Tab tab2 = new DocuSignAPI.Tab();
        tab2.Type_x = 'DateSigned';
        tab2.RecipientID = 1;
        tab2.DocumentID = 1;
        tab2.AnchorTabItem = new DocuSignAPI.AnchorTab();
        tab2.AnchorTabItem.AnchorTabString = 'd1';
        
        DocuSignAPI.Tab tab3 = new DocuSignAPI.Tab();
        tab3.Type_x = 'SignHere';
        tab3.RecipientID = 2;
        tab3.DocumentID = 1;
        tab3.AnchorTabItem = new DocuSignAPI.AnchorTab();
        tab3.AnchorTabItem.AnchorTabString = 's3';
        tab3.AnchorTabItem.YOffset = 10;
        
        DocuSignAPI.Tab tab4 = new DocuSignAPI.Tab();
        tab4.Type_x = 'Custom';
        tab4.RecipientID = 1;
        tab4.DocumentID = 1;
        tab4.AnchorTabItem = new DocuSignAPI.AnchorTab();
        tab4.AnchorTabItem.AnchorTabString = 'i1';
        tab4.CustomTabType = 'Checkbox';
        
        DocuSignAPI.Tab tab5 = new DocuSignAPI.Tab();
        tab5.Type_x = 'FullName';
        tab5.RecipientID = 1;
        tab5.DocumentID = 1;
        tab5.AnchorTabItem = new DocuSignAPI.AnchorTab();
        tab5.AnchorTabItem.AnchorTabString = 's1';
        tab5.AnchorTabItem.YOffset = 50;
        
        DocuSignAPI.Tab tab6 = new DocuSignAPI.Tab();
        tab6.Type_x = 'FullName';
        tab6.RecipientID = 2;
        tab6.DocumentID = 1;
        tab6.AnchorTabItem = new DocuSignAPI.AnchorTab();
        tab6.AnchorTabItem.AnchorTabString = 's3';
        tab6.AnchorTabItem.YOffset = 50;
        
        System.debug('Tabs created');
        envelope.Tabs.Tab[0] = tab1;        
        envelope.Tabs.Tab[1] = tab2;  
        envelope.Tabs.Tab[2] = tab3;
        envelope.Tabs.Tab[3] = tab4;
        envelope.Tabs.Tab[4] = tab5;
        envelope.Tabs.Tab[5] = tab6; 
    
        return envelope;
    }

    // Get the proxy for the dsapi-send wsdl
    public DocuSignAPI.APIServiceSoap dsapi_send() {
        // Get DSapi and authenticate
        DocuSignAPI.APIServiceSoap dsApiSend = new DocuSignAPI.APIServiceSoap();
        dsApiSend.endpoint_x = getDocuSignEndpoint();
        dsApiSend.inputHttpHeaders_x = new Map<String, String>();
        dsApiSend.inputHttpHeaders_x.put('X-DocuSign-Authentication', getAuth());
        return dsApiSend;
    }

    // Get the proxy for the dsapi-status wsdl
    public DocuSignAPI_status.APIServiceSoap dsapi_status() {
        // Get DSapi and authenticate
        DocuSignAPI_status.APIServiceSoap dsApiStatus = new DocuSignAPI_status.APIServiceSoap();
        dsApiStatus.endpoint_x = getDocuSignEndpoint();
        dsApiStatus.inputHttpHeaders_x = new Map<String, String>();
        dsApiStatus.inputHttpHeaders_x.put('X-DocuSign-Authentication', getAuth());
        return dsApiStatus;
    }

    public PageReference startDocuSignEmbeddedNextRecipient() {

        System.debug('Entering startDocuSignEmbeddedSecond()');   

        DocuSignAPI.ApiServiceSOAP dsApiSend = dsapi_send();

        DocuSignAPI.RequestRecipientTokenAuthenticationAssertion assertion = buildRequestRecipientTokenAuthenticationAssertion();

        DocuSignAPI.RequestRecipientTokenClientURLs clientURLs = buildRequestRequestRecipientTokenClientURLs(envelopeID);

        // assumes apiService = preconfigured api proxy
        try {
             tokenURL = dsApiSend.RequestRecipientToken(envelopeId, nextRecipientClientUserId, nextRecipientName, nextRecipientEmail, assertion, clientURLs);
        }  catch ( CalloutException e) {
            System.debug('Exception - ' + e );
            return errorPage;
        }

        PageReference pageRef = new PageReference(tokenURL);       
        return pageRef;

    }

    public PageReference docuSignOnCompletePageOpen() {

        PageReference nextWindow;
        envelopeId = ApexPages.currentPage().getParameters().get('envelopeid');
        System.debug('envelopeId : ' + envelopeId );

        DocuSignAPI_status.ApiServiceSOAP dsApiStatus = dsapi_status();
        DocuSignAPI_status.EnvelopeStatus envelopeStatus = dsApiStatus.RequestStatus(envelopeId);

        System.debug('envelopeStatus: ' + envelopeStatus.Status);

        if(!envelopeStatus.Status.equals('Sent')) {
            nextWindow = Page.DocuSignEnvelopeComplete;
            nextWindow.setRedirect(true);            
            return nextWindow;
        }

        DocuSignAPI_status.ArrayOfRecipientStatus recipientStatuses = envelopeStatus.RecipientStatuses;

        //Check for next recipient to sign
        for (DocuSignAPI_status.RecipientStatus recipient: recipientStatuses.RecipientStatus) {
            System.debug('status: ' + recipient.status);
            if(recipient.status.equals('Sent')) {
                System.debug('Found next to sign:' + recipient.UserName);
                nextRecipientName = recipient.UserName;
                nextRecipientEmail = recipient.Email;
                nextRecipientClientUserId = recipient.ClientUserId;
            }
        }

        return null;
    }
    
        public String getAuth() {

            DocuSignCredential__c credential = [SELECT Username__c, Password__c, IntegratorKey__c, AccountId__c, Endpoint__c FROM DocuSignCredential__c where Name = 'DocuSignAPICredential'];
            
            String authHeader = '<DocuSignCredentials><Username>'+ credential.Username__c +'</Username><Password>' + credential.Password__c + '</Password><IntegratorKey>' + credential.IntegratorKey__c + '</IntegratorKey></DocuSignCredentials>';
            return authHeader;
        }
        
        public String getDocuSignEndpoint() {

            DocuSignCredential__c credential = [SELECT Endpoint__c FROM DocuSignCredential__c where Name = 'DocuSignAPICredential'];
            
            String endpoint = credential.Endpoint__c;
            System.debug('DocuSign endpoint: [' + endpoint + ']');
            return endpoint;
        }
        
        public String getDocuSignAccountId() {

            DocuSignCredential__c credential = [SELECT AccountId__c FROM DocuSignCredential__c where Name = 'DocuSignAPICredential'];
            
            String accountId = credential.AccountId__c;
            System.debug('DocuSign accountId: [' + accountId + ']');
            return accountId ;
        }
        
        public String getSFEnvironmentURL() {

            DocuSignCredential__c credential = [SELECT SFEnvironmentURL__c FROM DocuSignCredential__c where Name = 'DocuSignAPICredential'];
            
            String environmentURL = credential.SFEnvironmentURL__c;
            System.debug('environmentURL : [' + environmentURL + ']');
            
            return environmentURL;
        }
}