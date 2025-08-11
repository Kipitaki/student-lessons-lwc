public with sharing class StudentLessonService {

    // ===== DTOs =====
    public class LessonStepData {
        @AuraEnabled public String id;                 // Lesson_Step__c Id (template step)
        @AuraEnabled public Integer stepNumber;
        @AuraEnabled public String instruction;
        @AuraEnabled public Integer duration;
        @AuraEnabled public Boolean completed;
        @AuraEnabled public Datetime completedDate;
    }

    public class StudentLessonData {
        @AuraEnabled public String id;                 // Student_Lesson__c Id (scheduled lesson)
        @AuraEnabled public Date lessonDate;
        @AuraEnabled public String lessonName;
        @AuraEnabled public List<LessonStepData> steps;

        // Lesson-level progress
        @AuraEnabled public Integer completedSteps;
        @AuraEnabled public Integer totalSteps;
        @AuraEnabled public Boolean completed;
    }

    // Mutation response wrapper
    public class StepUpdateResult {
        @AuraEnabled public String lessonId;
        @AuraEnabled public String stepId;
        @AuraEnabled public Boolean completed;
        @AuraEnabled public Datetime completedDate;

        // Updated lesson-level progress after the change
        @AuraEnabled public Integer completedSteps;
        @AuraEnabled public Integer totalSteps;
        @AuraEnabled public Boolean lessonCompleted;
    }

    // ===== Queries =====
    @AuraEnabled(cacheable=true)
    public static List<StudentLessonData> getLessonsForStudent(Id studentId) {
        List<Student_Lesson__c> studentLessons = [
            SELECT Id, Lesson_Date__c, Lesson__c
            FROM Student_Lesson__c
            WHERE Student__c = :studentId
            ORDER BY Lesson_Date__c ASC
        ];
        if (studentLessons.isEmpty()) return new List<StudentLessonData>();

        Set<Id> lessonIds = new Set<Id>();
        for (Student_Lesson__c sl : studentLessons) if (sl.Lesson__c != null) lessonIds.add(sl.Lesson__c);
        if (lessonIds.isEmpty()) return new List<StudentLessonData>();

        Map<Id, Lesson__c> lessonsById = new Map<Id, Lesson__c>([
            SELECT Id, Name,
                   (SELECT Id, Step_Number__c, Name, Duration__c
                    FROM Lesson_Steps__r
                    ORDER BY Step_Number__c ASC)
            FROM Lesson__c
            WHERE Id IN :lessonIds
        ]);

        Set<Id> studentLessonIds = new Set<Id>();
        for (Student_Lesson__c sl : studentLessons) studentLessonIds.add(sl.Id);

        Map<String, Student_Lesson_Step__c> progressByKey = new Map<String, Student_Lesson_Step__c>();
        if (!studentLessonIds.isEmpty()) {
            for (Student_Lesson_Step__c sls : [
                SELECT Id, Student_Lesson__c, Lesson_Step__c, Completed__c, CompletedDate__c
                FROM Student_Lesson_Step__c
                WHERE Student_Lesson__c IN :studentLessonIds
            ]) {
                progressByKey.put(String.valueOf(sls.Student_Lesson__c) + ':' + String.valueOf(sls.Lesson_Step__c), sls);
            }
        }

        List<StudentLessonData> result = new List<StudentLessonData>();
        for (Student_Lesson__c sl : studentLessons) {
            Lesson__c tmpl = lessonsById.get(sl.Lesson__c);
            if (tmpl == null) continue;

            StudentLessonData dto = new StudentLessonData();
            dto.id = String.valueOf(sl.Id);
            dto.lessonDate = sl.Lesson_Date__c;
            dto.lessonName = tmpl.Name;
            dto.steps = new List<LessonStepData>();

            Integer total = 0, done = 0;

            for (Lesson_Step__c step : tmpl.Lesson_Steps__r) {
                total++;
                LessonStepData sd = new LessonStepData();
                sd.id = String.valueOf(step.Id);
                sd.stepNumber = (step.Step_Number__c == null) ? null : Integer.valueOf(step.Step_Number__c);
                sd.instruction = step.Name;
                sd.duration = (step.Duration__c == null) ? null : Integer.valueOf(step.Duration__c);

                String pKey = String.valueOf(sl.Id) + ':' + String.valueOf(step.Id);
                Student_Lesson_Step__c prog = progressByKey.get(pKey);
                sd.completed = (prog != null && prog.Completed__c == true);
                sd.completedDate = (prog != null) ? prog.CompletedDate__c : null;

                if (sd.completed == true) done++;

                dto.steps.add(sd);
            }

            dto.totalSteps = total;
            dto.completedSteps = done;
            dto.completed = (total > 0 && done == total);

            result.add(dto);
        }
        return result;
    }

    // ===== Mutations =====
    @AuraEnabled
    public static StepUpdateResult setStepCompleted(Id studentLessonId, Id lessonStepId, Boolean completed) {
        if (studentLessonId == null || lessonStepId == null) {
            throw new AuraHandledException('studentLessonId and lessonStepId are required.');
        }

        Student_Lesson_Step__c sls;
        try {
            sls = [
                SELECT Id
                FROM Student_Lesson_Step__c
                WHERE Student_Lesson__c = :studentLessonId
                AND Lesson_Step__c = :lessonStepId
                LIMIT 1
            ];
        } catch (QueryException qe) {
            sls = null;
        }

        if (sls == null) {
            sls = new Student_Lesson_Step__c(
                Student_Lesson__c = studentLessonId,
                Lesson_Step__c = lessonStepId
            );
        }

        sls.Completed__c = completed;
        sls.CompletedDate__c = completed ? Datetime.now() : null;
        upsert sls;

        // Recompute lesson-level counts
        Id lessonId = [
            SELECT Lesson__c FROM Student_Lesson__c WHERE Id = :studentLessonId
        ].Lesson__c;

        Integer total = [
            SELECT COUNT() FROM Lesson_Step__c WHERE Lesson__c = :lessonId
        ];
        Integer done = [
            SELECT COUNT()
            FROM Student_Lesson_Step__c
            WHERE Student_Lesson__c = :studentLessonId AND Completed__c = true
        ];

        StepUpdateResult out = new StepUpdateResult();
        out.lessonId = String.valueOf(studentLessonId);
        out.stepId = String.valueOf(lessonStepId);
        out.completed = completed;
        out.completedDate = sls.CompletedDate__c;
        out.totalSteps = total;
        out.completedSteps = done;
        out.lessonCompleted = (total > 0 && done == total);
        return out;
    }

    // Badges unchanged
    @AuraEnabled(cacheable=true)
    public static List<Badge__c> getBadgesForStudent(Id studentId) {
        return [
            SELECT Id, Name, Badge_Type__c, Icon_Name__c, Lesson__r.Name, Award_Date__c
            FROM Badge__c
            WHERE Student__c = :studentId
            ORDER BY Award_Date__c DESC
        ];
    }
}