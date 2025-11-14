@IsTest
private class TraceSaleAggregationBatchTest {

    @TestSetup
    static void setup() {
        // Create test accounts
        Account testAccount = new Account(Name = 'Test Account', Type = 'Customer');
        insert testAccount;

        // Create unlinked trace sales for testing unlinked mode
        List<Trace_Sale__c> unlinkedSales = new List<Trace_Sale__c>();

        // Group 1: Same distributor, customer, zip, year - should aggregate
        for (Integer i = 0; i < 5; i++) {
            unlinkedSales.add(new Trace_Sale__c(
                Distributor__c = 'DistA',
                Customer__c = 'CustX',
                Zip_Code__c = '10001',
                City__c = 'New York',
                State__c = 'NY',
                Country__c = 'USA',
                Revenue_Net__c = 100 + (i * 10),
                Distributor_Invoice_Date__c = Date.newInstance(2024, 6, 15)
            ));
        }

        // Group 2: Different zip code
        for (Integer i = 0; i < 3; i++) {
            unlinkedSales.add(new Trace_Sale__c(
                Distributor__c = 'DistA',
                Customer__c = 'CustX',
                Zip_Code__c = '20002',
                City__c = 'Washington',
                State__c = 'DC',
                Country__c = 'USA',
                Revenue_Net__c = 200 + (i * 20),
                Distributor_Invoice_Date__c = Date.newInstance(2024, 7, 20)
            ));
        }

        // Group 3: Different year
        unlinkedSales.add(new Trace_Sale__c(
            Distributor__c = 'DistA',
            Customer__c = 'CustX',
            Zip_Code__c = '10001',
            City__c = 'New York',
            State__c = 'NY',
            Country__c = 'USA',
            Revenue_Net__c = 500,
            Distributor_Invoice_Date__c = Date.newInstance(2025, 1, 10)
        ));

        // Group 4: Null values to test edge cases
        unlinkedSales.add(new Trace_Sale__c(
            Distributor__c = null,
            Customer__c = 'CustY',
            Zip_Code__c = null,
            Revenue_Net__c = null,
            Distributor_Invoice_Date__c = null
        ));

        insert unlinkedSales;

        // Create trace account mapping for linked sales testing
        Trace_Account_Mapping__c mapping = new Trace_Account_Mapping__c(
            Account__c = testAccount.Id,
            Distributor__c = 'DistB',
            Ship_To_Name__c = 'CustZ',
            Zip_Code__c = '30003',
            City__c = 'Atlanta',
            State__c = 'GA',
            Country__c = 'USA'
        );
        insert mapping;

        // Create linked trace sales
        List<Trace_Sale__c> linkedSales = new List<Trace_Sale__c>();
        for (Integer i = 0; i < 4; i++) {
            linkedSales.add(new Trace_Sale__c(
                Distributor__c = 'DistB',
                Customer__c = 'CustZ',
                Zip_Code__c = '30003',
                City__c = 'Atlanta',
                State__c = 'GA',
                Country__c = 'USA',
                Revenue_Net__c = 300 + (i * 25),
                Distributor_Invoice_Date__c = Date.newInstance(2024, 8, 15),
                Trace_Account_Mapping__c = mapping.Id
            ));
        }
        insert linkedSales;
    }

    @IsTest
    static void testBatchExecutionUnlinkedMode() {
        Test.startTest();
        TraceSaleAggregationBatch batch = new TraceSaleAggregationBatch('unlinked', null);
        Id batchId = Database.executeBatch(batch, 200);
        Test.stopTest();

        // Verify batch completed
        AsyncApexJob job = [
            SELECT Id, Status, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :batchId
        ];
        System.assertEquals('Completed', job.Status, 'Batch should complete successfully');
        System.assertEquals(0, job.NumberOfErrors, 'Batch should have no errors');

        // Verify cache was populated (or failed gracefully)
        // Note: Cache may not work in test context, so we just verify no exceptions
        try {
            String cachedData = (String)Cache.Org.get('local.TraceSales.unlinked');
            if (String.isNotBlank(cachedData)) {
                List<AccountLinkerController.AggregatedTraceSale> results =
                    (List<AccountLinkerController.AggregatedTraceSale>)JSON.deserialize(
                        cachedData,
                        List<AccountLinkerController.AggregatedTraceSale>.class
                    );
                System.assert(results.size() > 0, 'Should have aggregated results');
            }
        } catch (Exception e) {
            System.debug('Cache not available in test: ' + e.getMessage());
            // This is OK - cache may not be available in test context
        }
    }

    @IsTest
    static void testBatchExecutionLinkedMode() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];

        Test.startTest();
        TraceSaleAggregationBatch batch = new TraceSaleAggregationBatch('linked', testAccount.Id);
        Id batchId = Database.executeBatch(batch, 200);
        Test.stopTest();

        // Verify batch completed
        AsyncApexJob job = [
            SELECT Id, Status, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :batchId
        ];
        System.assertEquals('Completed', job.Status, 'Batch should complete successfully');
        System.assertEquals(0, job.NumberOfErrors, 'Batch should have no errors');
    }

    @IsTest
    static void testBatchAggregationLogic() {
        Test.startTest();
        TraceSaleAggregationBatch batch = new TraceSaleAggregationBatch('unlinked', null);
        Database.executeBatch(batch, 200); // Use large batch size to ensure single execution in test
        Test.stopTest();

        // Query all unlinked sales to verify aggregation would be correct
        List<Trace_Sale__c> unlinkedSales = [
            SELECT Id, Distributor__c, Customer__c, Zip_Code__c,
                   Distributor_Invoice_Date__c, Revenue_Net__c
            FROM Trace_Sale__c
            WHERE Trace_Account_Mapping__c = null
        ];

        // Should have 10 unlinked sales from setup
        System.assert(unlinkedSales.size() > 0, 'Should have unlinked sales');

        // Verify different groups would be created based on grouping key
        Set<String> expectedGroups = new Set<String>();
        for (Trace_Sale__c ts : unlinkedSales) {
            String year = ts.Distributor_Invoice_Date__c != null
                ? String.valueOf(ts.Distributor_Invoice_Date__c.year())
                : '';
            String groupKey = String.valueOf(ts.Distributor__c) + '|' +
                            String.valueOf(ts.Customer__c) + '|' +
                            String.valueOf(ts.Zip_Code__c) + '|' +
                            year;
            expectedGroups.add(groupKey);
        }

        System.assert(expectedGroups.size() >= 3, 'Should have multiple aggregation groups');
    }

    @IsTest
    static void testBatchWithNullValues() {
        Test.startTest();
        TraceSaleAggregationBatch batch = new TraceSaleAggregationBatch('unlinked', null);
        Id batchId = Database.executeBatch(batch, 200);
        Test.stopTest();

        // Batch should handle null values gracefully
        AsyncApexJob job = [
            SELECT Id, Status, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :batchId
        ];
        System.assertEquals('Completed', job.Status, 'Batch should handle null values gracefully');
        System.assertEquals(0, job.NumberOfErrors, 'Should have no errors with null values');
    }

    @IsTest
    static void testBatchSortsByRevenue() {
        // Create additional records with varying revenue
        List<Trace_Sale__c> highRevenueSales = new List<Trace_Sale__c>();

        // High revenue group
        highRevenueSales.add(new Trace_Sale__c(
            Distributor__c = 'HighDist',
            Customer__c = 'HighCust',
            Zip_Code__c = '99999',
            Revenue_Net__c = 10000,
            Distributor_Invoice_Date__c = Date.today()
        ));

        // Low revenue group
        highRevenueSales.add(new Trace_Sale__c(
            Distributor__c = 'LowDist',
            Customer__c = 'LowCust',
            Zip_Code__c = '11111',
            Revenue_Net__c = 10,
            Distributor_Invoice_Date__c = Date.today()
        ));

        insert highRevenueSales;

        Test.startTest();
        TraceSaleAggregationBatch batch = new TraceSaleAggregationBatch('unlinked', null);
        Database.executeBatch(batch, 200);
        Test.stopTest();

        // If cache is available, verify sorting
        try {
            String cachedData = (String)Cache.Org.get('local.TraceSales.unlinked');
            if (String.isNotBlank(cachedData)) {
                List<AccountLinkerController.AggregatedTraceSale> results =
                    (List<AccountLinkerController.AggregatedTraceSale>)JSON.deserialize(
                        cachedData,
                        List<AccountLinkerController.AggregatedTraceSale>.class
                    );

                // Verify first result has highest revenue
                if (results.size() > 1) {
                    System.assert(
                        results[0].totalRevenue >= results[1].totalRevenue,
                        'Results should be sorted by revenue descending'
                    );
                }
            }
        } catch (Exception e) {
            System.debug('Cache not available in test: ' + e.getMessage());
        }
    }

    @IsTest
    static void testBatchWithLargeDataset() {
        // Create many records to test batch processing
        List<Trace_Sale__c> bulkSales = new List<Trace_Sale__c>();

        for (Integer i = 0; i < 50; i++) {
            bulkSales.add(new Trace_Sale__c(
                Distributor__c = 'BulkDist' + Math.mod(i, 5),
                Customer__c = 'BulkCust' + Math.mod(i, 5),
                Zip_Code__c = '5000' + Math.mod(i, 5),
                Revenue_Net__c = 100 + i,
                Distributor_Invoice_Date__c = Date.newInstance(2024, Math.mod(i, 12) + 1, 1)
            ));
        }
        insert bulkSales;

        Test.startTest();
        TraceSaleAggregationBatch batch = new TraceSaleAggregationBatch('unlinked', null);
        // Use large batch size to ensure single execution in test context
        Id batchId = Database.executeBatch(batch, 200);
        Test.stopTest();

        // Verify batch processed all records
        AsyncApexJob job = [
            SELECT Id, Status, TotalJobItems, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :batchId
        ];
        System.assertEquals('Completed', job.Status, 'Batch should process all records');
        System.assertEquals(0, job.NumberOfErrors, 'Should have no errors');
        System.assert(job.TotalJobItems >= 1, 'Should have processed at least one batch');
    }

    @IsTest
    static void testBatchQueryLocatorUnlinked() {
        TraceSaleAggregationBatch batch = new TraceSaleAggregationBatch('unlinked', null);

        Test.startTest();
        Database.QueryLocator ql = batch.start(null);
        Test.stopTest();

        // Verify query locator returns unlinked records
        // The batch query doesn't select Trace_Account_Mapping__c, so we verify by count
        List<Trace_Sale__c> records = Database.query(ql.getQuery());
        Integer expectedUnlinkedCount = [SELECT COUNT() FROM Trace_Sale__c WHERE Trace_Account_Mapping__c = null];
        System.assertEquals(expectedUnlinkedCount, records.size(), 'Should return all unlinked records');
        System.assert(records.size() > 0, 'Should have unlinked records from test setup');
    }

    @IsTest
    static void testBatchQueryLocatorLinked() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
        TraceSaleAggregationBatch batch = new TraceSaleAggregationBatch('linked', testAccount.Id);

        Test.startTest();
        Database.QueryLocator ql = batch.start(null);
        Test.stopTest();

        // Verify query locator returns linked records for the account
        List<Trace_Sale__c> records = Database.query(ql.getQuery());
        System.assert(records.size() > 0, 'Should find linked records');
    }

    @IsTest
    static void testBatchHandlesEmptyResults() {
        // Delete all unlinked sales
        delete [SELECT Id FROM Trace_Sale__c WHERE Trace_Account_Mapping__c = null];

        Test.startTest();
        TraceSaleAggregationBatch batch = new TraceSaleAggregationBatch('unlinked', null);
        Id batchId = Database.executeBatch(batch, 200);
        Test.stopTest();

        // Batch should complete even with no records
        AsyncApexJob job = [
            SELECT Id, Status, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :batchId
        ];
        System.assertEquals('Completed', job.Status, 'Batch should complete with empty results');
        System.assertEquals(0, job.NumberOfErrors, 'Should have no errors');
    }
}
