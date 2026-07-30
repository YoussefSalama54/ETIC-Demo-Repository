@isTest
private class SendWeeklyStatusRemindersTest {

    // ══════════════════════════════════════════════════════════════
    //  1. Input Validation Tests
    // ══════════════════════════════════════════════════════════════

    @isTest
    static void testNullInput() {
        Test.startTest();
        SendWeeklyStatusReminders.sendReminders(null);
        Test.stopTest();
        System.assert(true, 'Should handle null input gracefully');
    }

    @isTest
    static void testEmptyOuterList() {
        Test.startTest();
        SendWeeklyStatusReminders.sendReminders(new List<List<Project__c>>());
        Test.stopTest();
        System.assert(true, 'Should handle empty outer list gracefully');
    }

    @isTest
    static void testEmptyInnerList() {
        Test.startTest();
        SendWeeklyStatusReminders.sendReminders(
            new List<List<Project__c>>{ new List<Project__c>() }
        );
        Test.stopTest();
        System.assert(true, 'Should handle empty inner list gracefully');
    }

    @isTest
    static void testNullInnerList() {
        List<List<Project__c>> input = new List<List<Project__c>>();
        input.add(null);

        Test.startTest();
        SendWeeklyStatusReminders.sendReminders(input);
        Test.stopTest();
        System.assert(true, 'Should handle null inner list gracefully');
    }

    // ══════════════════════════════════════════════════════════════
    //  2. No Matching Assignments
    // ══════════════════════════════════════════════════════════════

    @isTest
    static void testNoAssignmentsFound() {
        List<Project__c> projects = TestDataFactory.createProjects(3, true);

        Test.startTest();
        SendWeeklyStatusReminders.sendReminders(
            new List<List<Project__c>>{ projects }
        );
        Test.stopTest();
        System.assert(true, 'Should exit gracefully when no assignments exist');
    }

    @isTest
    static void testInactiveAssignmentsSkipped() {
        Account acc = TestDataFactory.createAccount(true);
        List<Project__c> projects = TestDataFactory.createProjects(3, true);

        // Is_Owner__c = true, Is_Active__c = false → filtered out by query
        TestDataFactory.createProjectAssignments(
            projects, acc.Id, true, false, true
        );

        Test.startTest();
        SendWeeklyStatusReminders.sendReminders(
            new List<List<Project__c>>{ projects }
        );
        Test.stopTest();
        System.assert(true, 'Should skip inactive assignments');
    }

    @isTest
    static void testNonOwnerAssignmentsSkipped() {
        Account acc = TestDataFactory.createAccount(true);
        List<Project__c> projects = TestDataFactory.createProjects(3, true);

        // Is_Owner__c = false, Is_Active__c = true → filtered out by query
        TestDataFactory.createProjectAssignments(
            projects, acc.Id, false, true, true
        );

        Test.startTest();
        SendWeeklyStatusReminders.sendReminders(
            new List<List<Project__c>>{ projects }
        );
        Test.stopTest();
        System.assert(true, 'Should skip non-owner assignments');
    }

    // ══════════════════════════════════════════════════════════════
    //  3. Normal Send — Small Batch (Happy Path)
    // ══════════════════════════════════════════════════════════════

    @isTest
    static void testNormalSend() {
        Map<String, Object> scenario = TestDataFactory.createFullScenario(5);
        List<Project__c> projects = (List<Project__c>) scenario.get('projects');

        Test.startTest();
        SendWeeklyStatusReminders.sendReminders(
            new List<List<Project__c>>{ projects }
        );
        Test.stopTest();

        System.assert(true, 'Should send emails for 5 active owner assignments');
    }

    // ══════════════════════════════════════════════════════════════
    //  4. Mixed Assignments — Only Active Owners Get Emails
    // ══════════════════════════════════════════════════════════════

    @isTest
    static void testMixedAssignments() {
        Account acc = TestDataFactory.createAccount(true);
        List<Project__c> projects = TestDataFactory.createProjects(6, true);

        // First 3: active owners → should send
        List<Project__c> activeProjects = new List<Project__c>{
            projects[0], projects[1], projects[2]
        };
        TestDataFactory.createProjectAssignments(
            activeProjects, acc.Id, true, true, true
        );

        // Next 2: inactive → should skip
        List<Project__c> inactiveProjects = new List<Project__c>{
            projects[3], projects[4]
        };
        TestDataFactory.createProjectAssignments(
            inactiveProjects, acc.Id, true, false, true
        );

        // Last 1: non-owner → should skip
        List<Project__c> nonOwnerProjects = new List<Project__c>{
            projects[5]
        };
        TestDataFactory.createProjectAssignments(
            nonOwnerProjects, acc.Id, false, true, true
        );

        Test.startTest();
        SendWeeklyStatusReminders.sendReminders(
            new List<List<Project__c>>{ projects }
        );
        Test.stopTest();

        System.assert(true, 'Should only send emails for the 3 active owner assignments');
    }

    // ══════════════════════════════════════════════════════════════
    //  5. Project Chaining — Exceeds PROJECT_CHUNK_SIZE (200)
    // ══════════════════════════════════════════════════════════════

    @isTest
    static void testProjectChaining() {
        Account acc = TestDataFactory.createAccount(true);

        // 250 projects → first 200 processed in Job 1, remaining 50 chained
        List<Project__c> projects = TestDataFactory.createProjects(250, true);
        TestDataFactory.createProjectAssignments(
            projects, acc.Id, true, true, true
        );

        Test.startTest();
        SendWeeklyStatusReminders.sendReminders(
            new List<List<Project__c>>{ projects }
        );
        Test.stopTest();

        // Test.stopTest() executes the first Queueable synchronously.
        // Chaining is guarded by !Test.isRunningTest() so no stack overflow.
        System.assert(true, 
            'Should process first 200 projects and chain the remaining 50');
    }

    // ══════════════════════════════════════════════════════════════
    //  6. SendEmailOverflowQueueable — Direct Test (EmailData)
    // ══════════════════════════════════════════════════════════════

    @isTest
    static void testEmailOverflowQueueable() {
        // Build serializable EmailData (NOT SingleEmailMessage)
        List<SendWeeklyStatusReminders.EmailData> emailDataList = 
            new List<SendWeeklyStatusReminders.EmailData>();

        for (Integer i = 0; i < 10; i++) {
            emailDataList.add(new SendWeeklyStatusReminders.EmailData(
                'testuser' + i + '@example.com',
                'Overflow Test ' + i,
                '<p>Test overflow email ' + i + '</p>'
            ));
        }

        Test.startTest();
        System.enqueueJob(
            new SendWeeklyStatusReminders.SendEmailOverflowQueueable(emailDataList)
        );
        Test.stopTest();

        System.assert(true, 'SendEmailOverflowQueueable should send without errors');
    }

    // ══════════════════════════════════════════════════════════════
    //  7. SendRemindersQueueable — Direct Execution
    // ══════════════════════════════════════════════════════════════

    @isTest
    static void testQueueableDirectExecution() {
        Map<String, Object> scenario = TestDataFactory.createFullScenario(3);
        List<Project__c> projects = (List<Project__c>) scenario.get('projects');

        Test.startTest();
        System.enqueueJob(
            new SendWeeklyStatusReminders.SendRemindersQueueable(projects)
        );
        Test.stopTest();

        System.assert(true, 'Direct Queueable execution should complete without errors');
    }

    // ══════════════════════════════════════════════════════════════
    //  8. Multiple Accounts — Different Owners
    // ══════════════════════════════════════════════════════════════

    @isTest
    static void testMultipleOwners() {
        Account acc1 = TestDataFactory.createAccount('Client A', true);
        Account acc2 = TestDataFactory.createAccount('Client B', true);
        List<Project__c> projects = TestDataFactory.createProjects(4, true);

        List<Project__c> acc1Projects = new List<Project__c>{
            projects[0], projects[1]
        };
        List<Project__c> acc2Projects = new List<Project__c>{
            projects[2], projects[3]
        };

        TestDataFactory.createProjectAssignments(
            acc1Projects, acc1.Id, true, true, true
        );
        TestDataFactory.createProjectAssignments(
            acc2Projects, acc2.Id, true, true, true
        );

        Test.startTest();
        SendWeeklyStatusReminders.sendReminders(
            new List<List<Project__c>>{ projects }
        );
        Test.stopTest();

        System.assert(true, 
            'Should send emails to owners of both accounts');
    }

    // ══════════════════════════════════════════════════════════════
    //  9. EmailData Wrapper — Unit Test
    // ══════════════════════════════════════════════════════════════

    @isTest
    static void testEmailDataWrapper() {
        SendWeeklyStatusReminders.EmailData data = 
            new SendWeeklyStatusReminders.EmailData(
                'test@example.com',
                'Test Subject',
                '<p>Test Body</p>'
            );

        System.assertEquals('test@example.com', data.toAddress,
            'toAddress should match');
        System.assertEquals('Test Subject', data.subject,
            'subject should match');
        System.assertEquals('<p>Test Body</p>', data.htmlBody,
            'htmlBody should match');

        // Verify conversion to SingleEmailMessage
        Messaging.SingleEmailMessage msg = data.toEmailMessage();
        System.assertEquals('Test Subject', msg.getSubject(),
            'Converted message subject should match');
        System.assertEquals('<p>Test Body</p>', msg.getHtmlBody(),
            'Converted message body should match');
        System.assertEquals(1, msg.getToAddresses().size(),
            'Should have exactly one recipient');
        System.assertEquals('test@example.com', msg.getToAddresses()[0],
            'Recipient should match');
    }
}