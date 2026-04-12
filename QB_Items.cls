/**
 * @class QB_Items
 * @description Handles the creation and synchronization of Salesforce Products (Product2)
 *              as Items in QuickBooks via the QuickBooks Online REST API.
 *              Relies on QuickBookTokenUtil for token validation/refresh and
 *              custom metadata (quickBook__mdt) for API configuration.
 */
public with sharing class QB_Items {

    /**
     * @method testCreateItem
     * @description Entry point for bulk-syncing unsynced Salesforce Products to QuickBooks.
     *              Queries all Product2 records that have not yet been assigned a QuickBooks
     *              external ID, creates a corresponding Item in QuickBooks for each,
     *              and then bulk-updates the modified Product2 records in Salesforce.
     *
     * @note This method assumes that createItem() mutates the productRecord in place
     *       (e.g., setting QBExternalId__c and sync_with_quickbooks__c) before returning it.
     *       The final `update products` persists those changes back to Salesforce.
     */
    public static void testCreateItem(){
        // Fetch all products not yet synced with QuickBooks (no external QB ID assigned)
        List<Product2> products = [SELECT Id, Name FROM Product2 WHERE QBExternalId__c = null];

        for (Product2 prod : products) {
            // TODO: Build a QB_ItemInput from the Product2 fields before calling createItem()
            //       Currently prod is passed without constructing the QB_ItemInput payload
            createItem(prod);
        }

        // Persist all updated product records (e.g., QBExternalId__c, sync flags) to Salesforce
        update products;
    }


    /**
     * @method createItem
     * @description Creates a single Item in QuickBooks Online by calling the QB Items API,
     *              then updates the corresponding Salesforce Product2 record with the
     *              returned QuickBooks Item ID and marks it as synced.
     *
     * @param item          A QB_ItemInput wrapper object containing the item payload
     *                      to be serialized and sent to QuickBooks.
     * @param productRecord The Salesforce Product2 record associated with this item.
     *                      Will be updated with the QB external ID upon success.
     *
     * @return Product2     The updated productRecord (with QBExternalId__c and
     *                      sync_with_quickbooks__c populated on success),
     *                      or the original unchanged record if the callout fails.
     */
    public static Product2 createItem(QB_ItemInput item, Product2 productRecord) {

        // ── Step 1: Load QuickBooks API configuration from Custom Metadata ───────────────
        // Fetches credentials, endpoints, and token info stored in the QB_Token metadata record
        List<quickBook__mdt> configList = [
            SELECT Environment__c, Production_Base_URL__c, Sandbox_Base_URL__c, realmId__c,
                   minorversion__c, access_token__c, refresh_token__c, expires_in_time__c
            FROM quickBook__mdt
            WHERE DeveloperName = 'QB_Token'
            LIMIT 1
        ];

        if (configList?.size() > 0) {
            quickBook__mdt config = configList.get(0);

            // ── Step 2: Resolve the Access Token ─────────────────────────────────────────
            // Start with the stored access token; replace it if the token has expired
            String accessToken = config.access_token__c;

            // Holds updated token fields in case a refresh is needed later for metadata update
            Map<String, Object> fieldWithValuesMap;

            Boolean isTokenValid = QuickBookTokenUtil.isValid(config);

            // If the token is expired, request a new one using the stored refresh token
            if (!isTokenValid) {
                fieldWithValuesMap = QuickBookTokenUtil.refreshToken(config);
                // Override the local accessToken variable with the newly obtained token
                // NOTE: This re-declaration shadows the outer accessToken — consider reassigning instead
                String accessToken = (String) fieldWithValuesMap.get('access_token');
            }

            // ── Step 3: Build the HTTP Request ───────────────────────────────────────────
            HttpRequest req = new HttpRequest();
            req.setMethod('POST');
            req.setHeader('content-type', 'application/json');
            req.setHeader('authorization', 'Bearer ' + accessToken); // OAuth 2.0 Bearer token
            req.setHeader('accept', 'application/json');

            // Determine the correct base URL based on the configured environment
            // Defaults to Production; switches to Sandbox if explicitly configured
            String endpoint = config.Production_Base_URL__c
                + '/v3/company/' + config.realmId__c
                + '/item?minorversion=' + config.minorversion__c;

            if (config.Environment__c.equalsIgnoreCase('Sandbox')) {
                endpoint = config.Sandbox_Base_URL__c
                    + '/v3/company/' + config.realmId__c
                    + '/item?minorversion=' + config.minorversion__c;
            }
            req.setEndpoint(endpoint);

            // Serialize the QB_ItemInput wrapper object to JSON for the request body
            String requestBody = System.JSON.serialize(item);
            req.setBody(requestBody);

            // ── Step 4: Execute the Callout and Handle the Response ──────────────────────
            try {
                HttpResponse res = new Http().send(req);

                if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
                    // ── Success: Parse the returned Item from QuickBooks ─────────────────
                    Map<String, Object> responseMap =
                        (Map<String, Object>) System.JSON.deserializeUntyped(res.getBody());

                    // The QB API returns the created item nested under the "Item" key
                    Object itemObj = responseMap.get('Item');
                    Map<String, Object> itemMap = (Map<String, Object>) itemObj;
                    System.debug(System.JSON.serializePretty(itemMap));

                    // TODO: Extract the QB Item ID from itemMap (e.g., (String)itemMap.get('Id'))
                    //       and assign it to productId before using it below
                    // NOTE: `productId` is currently undefined — this will cause a compile error
                    productRecord.QBExternalId__c      = productId;         // Store the QB Item ID on the product
                    productRecord.sync_with_quickbooks__c = true;           // Mark the product as synced

                    return productRecord; // Return the updated record to the caller

                } else {
                    // ── Non-2xx Response: Log the failure details for debugging ──────────
                    // NOTE: The debug messages reference "Customer" — update to "Item" for clarity
                    System.debug('Item creation failed in QuickBooks. Response body: ' + res.getBody());
                    System.debug('Item creation failed. Status: ' + res.getStatus());
                }

            } catch (CalloutException e) {
                // Handles HTTP-level errors (e.g., timeout, unreachable endpoint)
                System.debug('Callout error while creating item in QuickBooks: ' + e.getMessage());

            } catch (Exception ex) {
                // Catches any unexpected runtime errors during the callout or response parsing
                System.debug('Unexpected error while creating item in QuickBooks: ' + ex.getMessage());
            }

            // ── Step 5: Persist Refreshed Token to Custom Metadata (if refreshed) ───────
            // If a token refresh occurred earlier, save the new tokens back to metadata
            // so subsequent calls use the updated credentials without re-authenticating
            if (fieldWithValuesMap?.size() > 0) {
                System.debug('Persisting refreshed token values to Custom Metadata.');
                String fullName = 'quickBook.QB_Token';
                String label    = 'QB_Token';

                // NOTE: `fieldWithValueMap` (no 's') is a typo — should be `fieldWithValuesMap`
                CreateUpdateMetadataUtils.createUpdateMetadata(fullName, label, fieldWithValuesMap);
            }

        } else {
            // Metadata record not found — cannot proceed without API credentials
            // TODO: Add an appropriate error log, exception throw, or ApexPages message here
        }

        // Return the original (unmodified) productRecord if the callout did not succeed
        return productRecord;
    }
}
