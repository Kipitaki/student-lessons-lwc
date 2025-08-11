public class InstructorResult {
    @InvocableVariable public Id instructorId;
    @InvocableVariable public String instructorName;
    @InvocableVariable public Decimal distanceMiles;

    public InstructorResult(Id id, String name, Decimal miles) {
        this.instructorId = id;
        this.instructorName = name;
        this.distanceMiles = miles;
    }
}