public class FindInstructorsForFlow {

    public class RequestWrapper {
        @InvocableVariable(required=true)
        public Id studentId;
    }

    public class JsonInstructor {
        public String instructorId;
        public String instructorName;
        public Decimal distanceMiles;

        public JsonInstructor(String id, String name, Decimal miles) {
            this.instructorId = id;
            this.instructorName = name;
            this.distanceMiles = miles;
        }
    }

    public class JsonResponseWrapper {
        @InvocableVariable
        public String jsonResult;
    }

    @InvocableMethod(label='Find Instructors By Distance - JSON')
    public static List<JsonResponseWrapper> find(List<RequestWrapper> requests) {
        List<JsonResponseWrapper> output = new List<JsonResponseWrapper>();
        List<JsonInstructor> results = new List<JsonInstructor>();

        if (requests == null || requests.isEmpty() || requests[0].studentId == null) {
            JsonResponseWrapper empty = new JsonResponseWrapper();
            empty.jsonResult = '[]';
            output.add(empty);
            return output;
        }

        Id studentId = requests[0].studentId;

        Student__c student;
        try {
            student = [
                SELECT Id, Name, Student_Instrument__c, Postal_Code__c,
                       Postal_Code__r.Latitude__c, Postal_Code__r.Longitude__c
                FROM Student__c
                WHERE Id = :studentId
                LIMIT 1
            ];
        } catch (Exception e) {
            JsonResponseWrapper err = new JsonResponseWrapper();
            err.jsonResult = '[]';
            output.add(err);
            return output;
        }

        Double sLat = tryParse(student.Postal_Code__r.Latitude__c);
        Double sLon = tryParse(student.Postal_Code__r.Longitude__c);

        if (sLat == null || sLon == null || student.Student_Instrument__c == null) {
            JsonResponseWrapper none = new JsonResponseWrapper();
            none.jsonResult = '[]';
            output.add(none);
            return output;
        }

        List<Instructor__c> instructors = [
            SELECT Id, Name, Postal_Code__c, Postal_Code__r.Latitude__c, Postal_Code__r.Longitude__c
            FROM Instructor__c
            WHERE Instrument__c = :student.Student_Instrument__c
              AND Status__c = 'Active'
              AND Postal_Code__c != null
        ];

        for (Instructor__c inst : instructors) {
            Double iLat = tryParse(inst.Postal_Code__r.Latitude__c);
            Double iLon = tryParse(inst.Postal_Code__r.Longitude__c);

            if (iLat != null && iLon != null) {
                Decimal distKm = DistanceUtil.haversine(sLat, sLon, iLat, iLon);
                Decimal distMiles = distKm * 0.621371;
                results.add(new JsonInstructor(inst.Id, inst.Name, distMiles.setScale(2)));
            }
        }

        JsonResponseWrapper wrapper = new JsonResponseWrapper();
        wrapper.jsonResult = JSON.serializePretty(results);
        output.add(wrapper);
        return output;
    }

    private static Double tryParse(String val) {
        try {
            return val != null ? Double.valueOf(val) : null;
        } catch (Exception e) {
            return null;
        }
    }
}