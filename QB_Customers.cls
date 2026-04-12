/**
 * @class QB_Customers
 * @description Handles the creation and synchronization of QuickBooks Online Customers
 *              from Salesforce. Calls the QuickBooks Customers REST API endpoint,
 *              manages OAuth token validation/refresh, and persists refreshed tokens
 *              back to Custom Metadata for subsequent requests.
 *              Configuration (endpoints, credentials, environment) is read from the
 *              QB_Token Custom Metadata record.
 */
public with sharing class QB_Customers {

    /**
     * @method createCustomer
     * @description Creates a new Customer record in QuickBooks Online by serializing
     *              the provided QBCustomerInput object and sending it to the QB API.
     *              Automatically refreshes the access token if it has expired before
     *              making the callout, and persists the new token values to metadata afterward.
     *
     * @param customer  A QBCustomerInput wrapper object containing all the fields
     *                  needed to create the customer in QuickBooks (name, email, phone, etc.)
     */
    public static void createCustomer(QBCustomerInput customer) {

        // ── Step 1: Load QB API Configuration from Custom Metadata ───────────────────────
        // Fetches credentials, base URLs, realmId, and token info from the QB_Token record.
        // Using a SOQL query here instead of getInstance() to retrieve environment-specific
        // fields (Production_Base_URL__c, Sandbox_Base_URL__c) not available via getInstance().
        List<quickBook__mdt> configList = [
            SELECT Environment__c, Production_Base_URL__c, Sandbox_Base_URL__c, realmId__c,
                   minorversion__c, access_token__c, refresh_token__c, expires_in_time__c
            FROM quickBook__mdt
            WHERE DeveloperName = 'QB_Token'
            LIMIT 1
        ];

        // NOTE: The object type in the SELECT list is `quickBook__md` (missing trailing 't')
        //       — this is a typo and will cause a compile error. Should be `quickBook__mdt`.

        if (configList?.size() > 0) {
            quickBook__mdt config = configList.get(0);
            System.debug(config.access_token__c);

            // ── Step 2: Resolve the Access Token ─────────────────────────────────────────
            // Start with the stored access token; replace it below if the token has expired
            String accessToken = config.access_token__c;
            System.debug(accessToken);

            // Holds updated token fields returned by the refresh call, used later
            // to persist new token values back to Custom Metadata
            Map<String, Object> fieldWithValuesMap;

            Boolean isTokenValid = QuickBookTokenUtil.isValid(config);

            // If the stored token has expired, request a fresh one using the refresh token
            if (!isTokenValid) {
                fieldWithValuesMap = QuickBookTokenUtil.refreshToken(config);
                // Override the local accessToken with the newly obtained value
                // NOTE: Re-declaring `String accessToken` here shadows the outer variable —
                //       the outer accessToken used in the request header is never updated.
                //       Remove `String` to reassign the existing variable instead.
                String accessToken = (String) fieldWithValuesMap.get('access_token');
            }

            // ── Step 3: Build the HTTP Request ───────────────────────────────────────────
            HttpRequest req = new HttpRequest();
            req.setMethod('POST');
            req.setHeader('content-type', 'application/json');
            req.setHeader('authorization', 'Bearer ' + accessToken); // OAuth 2.0 Bearer token
            req.setHeader('accept', 'application/json');

            // Select the correct base URL based on the configured environment.
            // Defaults to Production; switches to Sandbox when explicitly set.
            String Endpoint = config.Production_Base_URL__c
                            + '/v3/company/' + config.realmId__c
                            + '/customer?minorversion=' + config.minorversion__c;

            if (config.Environment__c.equalsIgnoreCase('Sandbox')) {
                Endpoint = config.Sandbox_Base_URL__c
                         + '/v3/company/' + config.realmId__c
                         + '/customer?minorversion=' + config.minorversion__c;
            }
            req.setEndpoint(Endpoint);

            // Serialize the QBCustomerInput wrapper object into JSON for the request body
            String requestBody = System.JSON.serialize(customer);
            req.setBody(requestBody);

            // ── Step 4: Execute the Callout and Handle the Response ──────────────────────
            try {
                HttpResponse res = new Http().send(req);

                if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
                    // ── Success: Parse the Created Customer's ID from the Response ────────
                    Map<String, Object> responseMap =
                        (Map<String, Object>) System.JSON.deserializeUntyped(res.getBody());

                    // QuickBooks returns the new customer's ID in the top-level 'Id' field
                    // NOTE: responseMap.get('Id') returns Object, not String — cast is missing
                    String customerId = (String) responseMap.get('Id');
                    System.debug('Customer created with ID: ' + customerId);

                    // TODO: Consider storing customerId back on the related Salesforce record
                    //       (e.g., a Contact or Account external ID field) for future lookups

                } else {
                    // ── Non-2xx Response: Log failure details for debugging ───────────────
                    // NOTE: Both debug messages below report success — they should report failure
                    System.debug('Failed to create customer in QuickBooks. Response: ' + res.getBody());
                    System.debug('Failed to create customer. Status: ' + res.getStatus());
                }

            } catch (CalloutException e) {
                // Handles HTTP-level errors (e.g., network timeout, unreachable endpoint)
                System.debug('Callout error while creating customer: ' + e.getMessage());

            } catch (Exception ex) {
                // Handles unexpected runtime errors (e.g., JSON parsing failures)
                System.debug('General error while creating customer: ' + ex.getMessage());
            }

            // ── Step 5: Persist Refreshed Token to Custom Metadata (if refreshed) ───────
            // If the token was refreshed during this call, save the new values back to
            // metadata so the next request uses the updated credentials automatically
            if (fieldWithValuesMap?.size() > 0) {
                System.debug('Updating metadata with new token values.');
                String fullName = 'quickBook.QB_Token';
                String label    = 'QB_Token';

                // NOTE: `fieldWithValueMap` (no 's') is a typo — should be `fieldWithValuesMap`
                //       This will cause a compile error as the variable name doesn't exist
                CreateUpdateMetadataUtils.createUpdateMetadata(fullName, label, fieldWithValuesMap);
            }

        } else {
            // Metadata record not found — cannot proceed without API credentials
            // TODO: Add an appropriate error log, exception throw, or ApexPages message here
        }
    }


    /**
     * @method testCreateCustomer
     * @description Developer/testing utility that constructs a hardcoded QBCustomerInput
     *              and calls createCustomer() to verify end-to-end integration with QuickBooks.
     *              Not intended for production use — consider moving to a test class
     *              or removing once the integration is verified.
     */
    public static void testCreateCustomer() {
        // Build a sample customer payload with representative data
        QBCustomerInput customer = new QBCustomerInput();
        customer.DisplayName  = 'John Doe';
        customer.CompanyName  = 'Doe Enterprises';
        customer.FamilyName   = 'Doe';
        customer.GivenName    = 'John';
        customer.Notes        = 'Test customer created from Salesforce';
        customer.Suffix       = 'Jr.';
        customer.Title        = 'CEO';

        // Set the customer's primary email address
        QB_Customers.PrimaryEmailAddr email = new QB_Customers.PrimaryEmailAddr();
        email.Address              = 'john.doe@doeenterprises.com';
        customer.PrimaryEmailAddr  = email;

        // Set the customer's primary phone number
        QB_Customers.PrimaryPhone phone = new QB_Customers.PrimaryPhone();
        phone.FreeFormNumber   = '123-456-7890';
        customer.PrimaryPhone  = phone;

        // Trigger the customer creation callout
        createCustomer(customer);
    }
}
