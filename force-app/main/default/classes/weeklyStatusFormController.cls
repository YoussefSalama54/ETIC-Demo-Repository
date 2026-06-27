public with sharing class weeklyStatusFormController {
    
    @AuraEnabled(cacheable=true)
    public static List<Project__c> getProjects() {
        return [SELECT Id, Name, Start_Date__c FROM Project__c ORDER BY Name ASC];
    }
    
    @AuraEnabled
    public static Id saveFeedback(Feedback__c feedback) {
        
        if (feedback.Id == null) {
            insert feedback;
        } else {
            update feedback;
        }
        
        return feedback.Id;
    }
    @AuraEnabled
    public static Feedback__c getLatestDraft(Id projectId) {
        
        List<Feedback__c> drafts = [
        SELECT Id, Name, Project__c,
            Reporting_Week__c,
            At_Risk__c,
            Blocked__c,
            Completion__c,
            Project_Phase__c,
            Progress_Summary_or_Key_Accomplishments__c,
            Next_Week_s_plan__c,
            Planned_Activities_Deliverables__c,
            Risk_Blockers__c,
            Notes_for_Leadership__c,
            Team_Morale__c
        FROM Feedback__c
        WHERE  CreatedById = :UserInfo.getUserId()
        AND Status__c = 'Draft'
        ORDER BY CreatedDate DESC
        LIMIT 1
    ];
        
        if (drafts.isEmpty()) {
            return null;
        }
        
        return drafts[0];
    }
    @AuraEnabled(cacheable=false)
    public static List<ContentDocumentLink> getFeedbackFiles(Id recordId) {
        
        return [
        SELECT ContentDocumentId,
               ContentDocument.Title,
               ContentDocument.FileType,
               ContentDocument.FileExtension,
               ContentDocument.LatestPublishedVersionId
        FROM ContentDocumentLink
        WHERE LinkedEntityId = :recordId
        ORDER BY ContentDocument.CreatedDate DESC
    ];
    }
    @AuraEnabled
    public static void deleteFile(Id contentDocumentId, Id feedbackId) {
        
        ContentDocumentLink[] link = [
        SELECT Id
        FROM ContentDocumentLink
        WHERE ContentDocumentId = :contentDocumentId
        AND LinkedEntityId = :feedbackId
    ];
        if(link.isEmpty()) return;
        delete link;
    }
}