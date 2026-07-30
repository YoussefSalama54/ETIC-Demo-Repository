public with sharing class SendWeeklyStatusReminders {

    // ── Constants ──
    private static final Integer PROJECT_CHUNK_SIZE = 200;
    private static final Integer EMAIL_BATCH_SIZE   = 100;
    private static final Integer MAX_SEND_CALLS     = 10;

    // ══════════════════════════════════════════════════════════════
    //  Serializable email wrapper (replaces SingleEmailMessage 
    //  for Queueable storage)
    // ══════════════════════════════════════════════════════════════
    public class EmailData {
        public String toAddress;
        public String subject;
        public String htmlBody;

        public EmailData(String toAddress, String subject, String htmlBody) {
            this.toAddress = toAddress;
            this.subject   = subject;
            this.htmlBody  = htmlBody;
        }

        public Messaging.SingleEmailMessage toEmailMessage() {
            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setToAddresses(new List<String>{ this.toAddress });
            msg.setSubject(this.subject);
            msg.setHtmlBody(this.htmlBody);
            return msg;
        }
    }

    // ══════════════════════════════════════════════════════════════
    //  Entry Point — called by Flow
    // ══════════════════════════════════════════════════════════════
    @InvocableMethod(label='Send Weekly Status Reminders' 
                     description='Sends personalized reminder emails in bulk')
    public static void sendReminders(List<List<Project__c>> projectLists) {

        if (projectLists == null || projectLists.isEmpty() || 
            projectLists[0] == null || projectLists[0].isEmpty()) {
            return;
        }

        System.enqueueJob(new SendRemindersQueueable(projectLists[0]));
    }

    // ══════════════════════════════════════════════════════════════
    //  Queueable 1 — Project chunking + chaining
    // ══════════════════════════════════════════════════════════════
    public class SendRemindersQueueable implements Queueable {

        private List<Project__c> projects;

        public SendRemindersQueueable(List<Project__c> projects) {
            this.projects = projects;
        }

        public void execute(QueueableContext ctx) {

            List<Project__c> currentBatch = new List<Project__c>();
            List<Project__c> remaining    = new List<Project__c>();

            for (Integer i = 0; i < projects.size(); i++) {
                if (i < PROJECT_CHUNK_SIZE) {
                    currentBatch.add(projects[i]);
                } else {
                    remaining.add(projects[i]);
                }
            }

            processBatch(currentBatch);

            if (!remaining.isEmpty() && !Test.isRunningTest()) {
                System.enqueueJob(new SendRemindersQueueable(remaining));
            }
        }

        private void processBatch(List<Project__c> batchProjects) {

            Set<Id> projectIds = new Map<Id, Project__c>(batchProjects).keySet();

            List<Project_Assignment__c> projectAssignments = [
                SELECT Id, Account__c, Account__r.OwnerId, Project__c 
                FROM Project_Assignment__c 
                WHERE Project__c IN :projectIds 
                  AND Is_Owner__c = TRUE 
                  AND Is_Active__c = TRUE
            ];
            if (projectAssignments.isEmpty()) return;

            Set<Id> ownerIds = new Set<Id>();
            for (Project_Assignment__c pA : projectAssignments) {
                if (pA.Account__r != null && pA.Account__r.OwnerId != null) {
                    ownerIds.add(pA.Account__r.OwnerId);
                }
            }
            if (ownerIds.isEmpty()) return;

            Map<Id, User> userMap = new Map<Id, User>(
                [SELECT Id, Email, FirstName FROM User WHERE Id IN :ownerIds]
            );

            // ── Build serializable email data (NOT SingleEmailMessage) ──
            String baseUrl = URL.getOrgDomainURL().toExternalForm() + '/';
            List<EmailData> emailDataList = new List<EmailData>();

            for (Project_Assignment__c pA : projectAssignments) {
                if (pA.Account__r == null || pA.Account__r.OwnerId == null) continue;

                User owner = userMap.get(pA.Account__r.OwnerId);
                if (owner == null || String.isBlank(owner.Email)) continue;

                String safeName = String.isNotBlank(owner.FirstName) 
                    ? owner.FirstName.escapeHtml4() 
                    : '';
                String recordLink = baseUrl + pA.Project__c;
               

                String htmlBody = '<p>Hello ' + safeName + '</p>'
                    + '<p>Please use ' + '<a href=' +recordLink+'>this link</a>' + ' '
                    + 'to fill this week\'s report ASAP.</p>'
                    + '<p>Thank you</p>';

                emailDataList.add(new EmailData(
                    owner.Email,
                    'Project Weekly Status Form Reminder',
                    htmlBody
                ));
            }

            if (!emailDataList.isEmpty()) {
                sendInChunks(emailDataList);
            }
        }

        private void sendInChunks(List<EmailData> emailDataList) {

            List<String> errors = new List<String>();
            Integer sendCount = 0;

            for (Integer i = 0; i < emailDataList.size(); i += EMAIL_BATCH_SIZE) {

                if (sendCount >= MAX_SEND_CALLS) {
                    // ── Capture unsent as serializable EmailData ──
                    List<EmailData> unsent = new List<EmailData>();
                    for (Integer k = i; k < emailDataList.size(); k++) {
                        unsent.add(emailDataList[k]);
                    }
                    if (!Test.isRunningTest()) {
                        System.enqueueJob(new SendEmailOverflowQueueable(unsent));
                    }
                    break;
                }

                // ── Convert batch to SingleEmailMessage at send time ──
                Integer endIndex = Math.min(i + EMAIL_BATCH_SIZE, emailDataList.size());
                List<Messaging.SingleEmailMessage> batch = 
                    new List<Messaging.SingleEmailMessage>();

                for (Integer j = i; j < endIndex; j++) {
                    batch.add(emailDataList[j].toEmailMessage());
                }

                List<Messaging.SendEmailResult> results = 
                    Messaging.sendEmail(batch, false);

                sendCount++;

                for (Messaging.SendEmailResult r : results) {
                    if (!r.isSuccess()) {
                        for (Messaging.SendEmailError e : r.getErrors()) {
                            errors.add('Target: ' + e.getTargetObjectId() 
                                + ' | Error: ' + e.getMessage());
                        }
                    }
                }
            }

            if (!errors.isEmpty()) {
                System.debug(LoggingLevel.ERROR, 
                    'Weekly Status Reminder failures:\n' 
                    + String.join(errors, '\n'));
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    //  Queueable 2 — Email overflow (now stores serializable data)
    // ══════════════════════════════════════════════════════════════
    public class SendEmailOverflowQueueable implements Queueable {

        private List<EmailData> emailDataList;

        public SendEmailOverflowQueueable(List<EmailData> emailDataList) {
            this.emailDataList = emailDataList;
        }

        public void execute(QueueableContext ctx) {

            List<String> errors = new List<String>();
            Integer sendCount = 0;

            for (Integer i = 0; i < emailDataList.size(); i += EMAIL_BATCH_SIZE) {

                if (sendCount >= MAX_SEND_CALLS) {
                    List<EmailData> unsent = new List<EmailData>();
                    for (Integer k = i; k < emailDataList.size(); k++) {
                        unsent.add(emailDataList[k]);
                    }
                    if (!Test.isRunningTest()) {
                        System.enqueueJob(new SendEmailOverflowQueueable(unsent));
                    }
                    break;
                }

                Integer endIndex = Math.min(i + EMAIL_BATCH_SIZE, emailDataList.size());
                List<Messaging.SingleEmailMessage> batch = 
                    new List<Messaging.SingleEmailMessage>();

                for (Integer j = i; j < endIndex; j++) {
                    batch.add(emailDataList[j].toEmailMessage());
                }

                List<Messaging.SendEmailResult> results = 
                    Messaging.sendEmail(batch, false);

                sendCount++;

                for (Messaging.SendEmailResult r : results) {
                    if (!r.isSuccess()) {
                        for (Messaging.SendEmailError e : r.getErrors()) {
                            errors.add('Target: ' + e.getTargetObjectId() 
                                + ' | Error: ' + e.getMessage());
                        }
                    }
                }
            }

            if (!errors.isEmpty()) {
                System.debug(LoggingLevel.ERROR, 
                    'Email overflow batch failures:\n' 
                    + String.join(errors, '\n'));
            }
        }
    }
}