/**
 * Handler class for TraceSaleTrigger
 * Manages aggregation key population for efficient GROUP BY queries
 */
public class TraceSaleTriggerHandler {

    /**
     * Populates the Aggregation_Key__c field based on grouping criteria
     * Format: Distributor|Customer|ZipCode|Year
     */
    public static void populateAggregationKey(List<Trace_Sale__c> traceSales) {
        for (Trace_Sale__c ts : traceSales) {
            // Build aggregation key: Distributor|Customer|ZipCode|Year
            String distributor = ts.Distributor__c != null ? ts.Distributor__c : '';
            String customer = ts.Customer__c != null ? ts.Customer__c : '';
            String zipCode = ts.Zip_Code__c != null ? ts.Zip_Code__c : '';
            String year = '';

            if (ts.Distributor_Invoice_Date__c != null) {
                year = String.valueOf(ts.Distributor_Invoice_Date__c.year());
            }

            ts.Aggregation_Key__c = distributor + '|' + customer + '|' + zipCode + '|' + year;
        }
    }
}
