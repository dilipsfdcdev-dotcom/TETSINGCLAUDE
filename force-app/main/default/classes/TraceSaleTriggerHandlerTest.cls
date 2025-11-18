/**
 * Test class for TraceSaleTriggerHandler
 */
@IsTest
private class TraceSaleTriggerHandlerTest {

    @IsTest
    static void testAggregationKeyPopulation() {
        // Create test record
        Trace_Sale__c ts = new Trace_Sale__c(
            Distributor__c = 'TestDist',
            Customer__c = 'TestCust',
            Zip_Code__c = '12345',
            Revenue_Net__c = 1000,
            Distributor_Invoice_Date__c = Date.newInstance(2024, 6, 15)
        );

        Test.startTest();
        insert ts;
        Test.stopTest();

        // Verify aggregation key was populated correctly
        Trace_Sale__c inserted = [
            SELECT Aggregation_Key__c
            FROM Trace_Sale__c
            WHERE Id = :ts.Id
        ];

        System.assertEquals('TestDist|TestCust|12345|2024', inserted.Aggregation_Key__c,
            'Aggregation key should be populated on insert');
    }

    @IsTest
    static void testAggregationKeyWithNulls() {
        // Create test record with null values
        Trace_Sale__c ts = new Trace_Sale__c(
            Distributor__c = null,
            Customer__c = 'TestCust',
            Zip_Code__c = null,
            Revenue_Net__c = 500,
            Distributor_Invoice_Date__c = null
        );

        Test.startTest();
        insert ts;
        Test.stopTest();

        // Verify aggregation key handles nulls correctly
        Trace_Sale__c inserted = [
            SELECT Aggregation_Key__c
            FROM Trace_Sale__c
            WHERE Id = :ts.Id
        ];

        System.assertEquals('|TestCust||', inserted.Aggregation_Key__c,
            'Aggregation key should handle null values');
    }

    @IsTest
    static void testAggregationKeyUpdate() {
        // Create test record
        Trace_Sale__c ts = new Trace_Sale__c(
            Distributor__c = 'OldDist',
            Customer__c = 'OldCust',
            Zip_Code__c = '11111',
            Revenue_Net__c = 1000,
            Distributor_Invoice_Date__c = Date.newInstance(2023, 1, 1)
        );
        insert ts;

        // Update the record
        ts.Distributor__c = 'NewDist';
        ts.Customer__c = 'NewCust';
        ts.Zip_Code__c = '22222';
        ts.Distributor_Invoice_Date__c = Date.newInstance(2024, 12, 31);

        Test.startTest();
        update ts;
        Test.stopTest();

        // Verify aggregation key was updated
        Trace_Sale__c updated = [
            SELECT Aggregation_Key__c
            FROM Trace_Sale__c
            WHERE Id = :ts.Id
        ];

        System.assertEquals('NewDist|NewCust|22222|2024', updated.Aggregation_Key__c,
            'Aggregation key should be updated when fields change');
    }

    @IsTest
    static void testBulkAggregationKeyPopulation() {
        // Create multiple records
        List<Trace_Sale__c> traceSales = new List<Trace_Sale__c>();
        for (Integer i = 0; i < 200; i++) {
            traceSales.add(new Trace_Sale__c(
                Distributor__c = 'Dist' + Math.mod(i, 5),
                Customer__c = 'Cust' + Math.mod(i, 10),
                Zip_Code__c = '1000' + Math.mod(i, 3),
                Revenue_Net__c = 100 + i,
                Distributor_Invoice_Date__c = Date.newInstance(2024, Math.mod(i, 12) + 1, 1)
            ));
        }

        Test.startTest();
        insert traceSales;
        Test.stopTest();

        // Verify all records have aggregation keys
        List<Trace_Sale__c> inserted = [
            SELECT Aggregation_Key__c
            FROM Trace_Sale__c
            WHERE Id IN :traceSales
        ];

        System.assertEquals(200, inserted.size(), 'Should insert all records');
        for (Trace_Sale__c ts : inserted) {
            System.assertNotEquals(null, ts.Aggregation_Key__c, 'All records should have aggregation key');
            System.assert(ts.Aggregation_Key__c.contains('|'), 'Aggregation key should contain pipe delimiters');
        }
    }
}
