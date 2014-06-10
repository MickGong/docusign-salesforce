@isTest(SeeAllData=true)
public class DocuSignNowControllerTest{

    public static testMethod void testDocuSignNowController() {
    
       List<Opportunity> opportunities= [SELECT Id, Applicant_2_Name__c , Applicant_2_Email__c, Account.Name, Email__c FROM Opportunity where Name = 'Mark Kelly'];

       ApexPages.StandardController stdController = new ApexPages.StandardController(opportunities.get(0));
       
       List<Attachment> attachments = [SELECT Id, Name, Body, ContentType, BodyLength FROM Attachment where ParentId = :opportunities.get(0).Id];
       
       DocuSignNowController controller = new DocuSignNowController(stdController);

       //Example of calling an Action method. Same as calling any other Apex method. 
       //Normally this is executed by a user clicking a button or a link from the Visualforce
       //page, but in the test method, just test the action method the same as any 
       //other method by calling it directly. 

       //The .getURL will return the page url the Save() method returns.
       controller.buildEnvelope(attachments.get(0));
       
       DocuSignAPI.RequestRecipientTokenAuthenticationAssertion assertion = controller.buildRequestRecipientTokenAuthenticationAssertion();

       DocuSignAPI.RequestRecipientTokenClientURLs clientURLs = controller.buildRequestRequestRecipientTokenClientURLs('3');
       
       controller.getAuth();
       controller.getDocuSignEndpoint();
       controller.dsapi_send();
       controller.dsapi_status();

   }
   
 }