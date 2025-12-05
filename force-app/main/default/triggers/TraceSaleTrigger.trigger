/**
 * Trigger for Trace_Sale__c object
 * Handles aggregation key population
 */
trigger TraceSaleTrigger on Trace_Sale__c (before insert, before update) {
    if (Trigger.isBefore) {
        if (Trigger.isInsert || Trigger.isUpdate) {
            TraceSaleTriggerHandler.populateAggregationKey(Trigger.new);
        }
    }
}
