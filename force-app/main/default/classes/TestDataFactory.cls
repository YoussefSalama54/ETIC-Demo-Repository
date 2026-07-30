@isTest
public class TestDataFactory {

    // ── Account ──
    public static Account createAccount(String name, Boolean doInsert) {
        Account acc = new Account(Name = name);
        if (doInsert) insert acc;
        return acc;
    }

    public static Account createAccount(Boolean doInsert) {
        return createAccount('Test Client Account', doInsert);
    }

    // ── Projects ──
    public static List<Project__c> createProjects(Integer count, Boolean doInsert) {
        List<Project__c> projects = new List<Project__c>();
        for (Integer i = 0; i < count; i++) {
            projects.add(new Project__c(
                Name          = 'Test Project ' + i,
                Start_Date__c = System.today()
            ));
        }
        if (doInsert) insert projects;
        return projects;
    }

    public static Project__c createProject(String name, Boolean doInsert) {
        Project__c p = new Project__c(
            Name          = name,
            Start_Date__c = System.today()
        );
        if (doInsert) insert p;
        return p;
    }

    // ── Project Assignments ──
    public static List<Project_Assignment__c> createProjectAssignments(
        List<Project__c> projects,
        Id accountId,
        Boolean isOwner,
        Boolean isActive,
        Boolean doInsert
    ) {
        List<Project_Assignment__c> assignments = new List<Project_Assignment__c>();
        for (Project__c p : projects) {
            assignments.add(new Project_Assignment__c(
                Project__c   = p.Id,
                Account__c   = accountId,
                Is_Owner__c  = isOwner,
                Is_Active__c = isActive
            ));
        }
        if (doInsert) insert assignments;
        return assignments;
    }

    // Overload: defaults to isOwner = true, isActive = true
    public static List<Project_Assignment__c> createProjectAssignments(
        List<Project__c> projects,
        Id accountId,
        Boolean doInsert
    ) {
        return createProjectAssignments(projects, accountId, true, true, doInsert);
    }

    // ── Full Scenario Builder ──
    public static Map<String, Object> createFullScenario(Integer projectCount) {
        Account acc = createAccount(true);
        List<Project__c> projects = createProjects(projectCount, true);
        List<Project_Assignment__c> assignments =
            createProjectAssignments(projects, acc.Id, true);

        return new Map<String, Object>{
            'account'     => acc,
            'projects'    => projects,
            'assignments' => assignments
        };
    }
}