/**
 * BatchStudentInstructorMatcher
 * 
 * This batch class finds the closest matching instructor for each student
 * based on their instrument and geographic distance (using latitude/longitude).
 * It updates each student with the closest Instructor__c and stores the distance (in km).
 *
 * Assumes:
 * - Student__c has lookup fields: Student_Instrument__c, Postal_Code__c, Instructor__c
 * - Student__c has Distance__c field (Number) for storing distance in kilometers
 * - Postal_Code__c has Latitude__c and Longitude__c stored as text fields
 * - DistanceUtil.haversine(lat1, lon1, lat2, lon2) returns distance in kilometers
 */
public class BatchStudentInstructorMatcher implements Database.Batchable<SObject>, Database.Stateful {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Name, Student_Instrument__c, Postal_Code__r.Latitude__c, Postal_Code__r.Longitude__c
            FROM Student__c
            WHERE Student_Instrument__c != null AND Postal_Code__c != null
        ]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        System.debug('⚙️ Batch Scope Count: ' + scope.size());
        List<Student__c> studentsToUpdate = new List<Student__c>();

        for (Student__c student : (List<Student__c>) scope) {
            System.debug('🔍 Processing student: ' + student.Name);
            System.debug('🎼 Student instrument: ' + student.Student_Instrument__c);

            Double sLat = tryParse(student.Postal_Code__r.Latitude__c);
            Double sLon = tryParse(student.Postal_Code__r.Longitude__c);

            System.debug('📌 Parsed student coordinates: ' + sLat + ', ' + sLon);

            if (sLat == null || sLon == null) {
                System.debug('⚠️ Skipping student due to missing coordinates');
                continue;
            }

            List<Instructor__c> matchingInstructors = [
                SELECT Id, Name, Postal_Code__r.Latitude__c, Postal_Code__r.Longitude__c, Instrument__c
                FROM Instructor__c
                WHERE Instrument__c = :student.Student_Instrument__c AND Postal_Code__c != null AND Status__c = 'Active'
            ];

            System.debug('👀 Instructor query ran with instrument: ' + student.Student_Instrument__c + ' and returned ' + matchingInstructors.size() + ' instructors');

            Instructor__c closestInstructor = null;
            Double shortestDistance = null;

            for (Instructor__c instructor : matchingInstructors) {
                System.debug('📍 Instructor: ' + instructor.Name +
                             ' | Instrument: ' + instructor.Instrument__c +
                             ' | Lat: ' + instructor.Postal_Code__r.Latitude__c +
                             ' | Lon: ' + instructor.Postal_Code__r.Longitude__c);

                Double iLat = tryParse(instructor.Postal_Code__r.Latitude__c);
                Double iLon = tryParse(instructor.Postal_Code__r.Longitude__c);

                System.debug('📌 Parsed instructor coordinates: ' + iLat + ', ' + iLon);

                if (iLat == null || iLon == null) {
                    System.debug('⚠️ Skipping instructor due to missing coordinates: ' + instructor.Name);
                    continue;
                }

                Double dist = DistanceUtil.haversine(sLat, sLon, iLat, iLon);
                System.debug('📏 Distance from ' + student.Name + ' to ' + instructor.Name + ': ' + dist);

                if (shortestDistance == null || dist < shortestDistance) {
                    shortestDistance = dist;
                    closestInstructor = instructor;
                }
            }

            if (closestInstructor != null) {
                System.debug('✅ Closest instructor to ' + student.Name + ' is ' + closestInstructor.Name + ' at ' + shortestDistance + ' km');
                student.Instructor__c = closestInstructor.Id;
                student.Distance__c = shortestDistance;
                studentsToUpdate.add(student);
            } else {
                System.debug('❌ No matching instructor found for student: ' + student.Name);
            }
        }

        if (!studentsToUpdate.isEmpty()) {
            update studentsToUpdate;
            System.debug('💾 Updated ' + studentsToUpdate.size() + ' students.');
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('🏁 Batch finished');
    }

    private Double tryParse(String val) {
        try {
            return val != null ? Double.valueOf(val) : null;
        } catch (Exception e) {
            System.debug('❗ Failed to parse coordinate: ' + val);
            return null;
        }
    }
} 

/**
 * Utility class assumed available in your org:
 * public class DistanceUtil {
 *     public static Double haversine(Double lat1, Double lon1, Double lat2, Double lon2) {
 *         // Haversine formula implementation
 *     }
 * }
 */