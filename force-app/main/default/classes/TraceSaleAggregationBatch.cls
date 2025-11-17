/**
 * Batch Apex to process all Trace Sales and compute aggregations
 * Handles datasets larger than 50K by processing in chunks
 */
public class TraceSaleAggregationBatch implements Database.Batchable<sObject>, Database.Stateful {

    private String mode; // 'unlinked' or 'linked'
    private String accountId;
    private Map<String, AggregationData> aggregationMap;

    public class AggregationData {
        public String distributor;
        public String customer;
        public String zipCode;
        public String city;
        public String state;
        public String country;
        public String timePeriod;
        public Decimal totalRevenue = 0;
        public Integer recordCount = 0;
    }

    public TraceSaleAggregationBatch(String mode, String accountId) {
        this.mode = mode;
        this.accountId = accountId;
        this.aggregationMap = new Map<String, AggregationData>();
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        String query = 'SELECT Id, Distributor__c, Customer__c, Zip_Code__c, City__c, State__c, Country__c, ' +
                       'Distributor_Invoice_Date__c, Revenue_Net__c ' +
                       'FROM Trace_Sale__c ';

        if (mode == 'unlinked') {
            query += 'WHERE Trace_Account_Mapping__c = null';
        } else if (mode == 'linked' && String.isNotBlank(accountId)) {
            query += 'WHERE Trace_Account_Mapping__r.Account__c = \'' + String.escapeSingleQuotes(accountId) + '\'';
        }

        query += ' ORDER BY Id';

        return Database.getQueryLocator(query);
    }

    public void execute(Database.BatchableContext bc, List<Trace_Sale__c> scope) {
        for (Trace_Sale__c ts : scope) {
            // Extract year from date
            String year = '';
            if (ts.Distributor_Invoice_Date__c != null) {
                year = String.valueOf(ts.Distributor_Invoice_Date__c.year());
            }

            // Create grouping key
            String groupKey =
                String.valueOf(ts.Distributor__c) + '|' +
                String.valueOf(ts.Customer__c) + '|' +
                String.valueOf(ts.Zip_Code__c) + '|' +
                year;

            // Get or create aggregation data
            AggregationData aggData;
            if (aggregationMap.containsKey(groupKey)) {
                aggData = aggregationMap.get(groupKey);
            } else {
                aggData = new AggregationData();
                aggData.distributor = ts.Distributor__c;
                aggData.customer = ts.Customer__c;
                aggData.zipCode = ts.Zip_Code__c;
                aggData.city = ts.City__c;
                aggData.state = ts.State__c;
                aggData.country = ts.Country__c;
                aggData.timePeriod = year;
                aggregationMap.put(groupKey, aggData);
            }

            // Aggregate values
            if (ts.Revenue_Net__c != null) {
                aggData.totalRevenue += ts.Revenue_Net__c;
            }
            aggData.recordCount++;
        }
    }

    public void finish(Database.BatchableContext bc) {
        // Convert aggregation map to wrapper objects
        List<AccountLinkerController.AggregatedTraceSale> results =
            new List<AccountLinkerController.AggregatedTraceSale>();

        for (String groupKey : aggregationMap.keySet()) {
            AggregationData aggData = aggregationMap.get(groupKey);

            AccountLinkerController.AggregatedTraceSale agg =
                new AccountLinkerController.AggregatedTraceSale();
            agg.groupKey = groupKey;
            agg.distributor = aggData.distributor != null ? aggData.distributor : '';
            agg.customer = aggData.customer != null ? aggData.customer : '';
            agg.zipCode = aggData.zipCode != null ? aggData.zipCode : '';
            agg.city = aggData.city != null ? aggData.city : '';
            agg.state = aggData.state != null ? aggData.state : '';
            agg.country = aggData.country != null ? aggData.country : '';
            agg.timePeriod = aggData.timePeriod;
            agg.totalRevenue = aggData.totalRevenue;
            agg.recordCount = aggData.recordCount;
            agg.traceSaleIds = new List<String>();
            agg.contractNames = '';

            results.add(agg);
        }

        // Sort by revenue descending
        results = sortByRevenue(results);

        // Store in Platform Cache (max 50MB)
        // Cache keys must be alphanumeric only (no underscores)
        try {
            Cache.Org.put('local.TraceSales.' + mode,
                          JSON.serialize(results),
                          3600); // 1 hour TTL

            System.debug('Stored ' + results.size() + ' aggregated groups in cache for mode: ' + mode);
        } catch (Exception e) {
            System.debug('Error storing in cache: ' + e.getMessage());
        }
    }

    /**
     * Sort by revenue using merge sort (O(n log n)) for better performance
     */
    private List<AccountLinkerController.AggregatedTraceSale> sortByRevenue(
        List<AccountLinkerController.AggregatedTraceSale> results
    ) {
        if (results == null || results.size() <= 1) {
            return results;
        }
        return mergeSort(results, 0, results.size() - 1);
    }

    private List<AccountLinkerController.AggregatedTraceSale> mergeSort(
        List<AccountLinkerController.AggregatedTraceSale> arr, Integer left, Integer right
    ) {
        if (left >= right) {
            return new List<AccountLinkerController.AggregatedTraceSale>{ arr[left] };
        }

        Integer mid = left + (right - left) / 2;
        List<AccountLinkerController.AggregatedTraceSale> leftSorted = mergeSort(arr, left, mid);
        List<AccountLinkerController.AggregatedTraceSale> rightSorted = mergeSort(arr, mid + 1, right);

        return mergeLists(leftSorted, rightSorted);
    }

    private List<AccountLinkerController.AggregatedTraceSale> mergeLists(
        List<AccountLinkerController.AggregatedTraceSale> left,
        List<AccountLinkerController.AggregatedTraceSale> right
    ) {
        List<AccountLinkerController.AggregatedTraceSale> result =
            new List<AccountLinkerController.AggregatedTraceSale>();
        Integer i = 0, j = 0;

        while (i < left.size() && j < right.size()) {
            if (left[i].totalRevenue >= right[j].totalRevenue) {
                result.add(left[i]);
                i++;
            } else {
                result.add(right[j]);
                j++;
            }
        }

        while (i < left.size()) {
            result.add(left[i]);
            i++;
        }

        while (j < right.size()) {
            result.add(right[j]);
            j++;
        }

        return result;
    }
}
