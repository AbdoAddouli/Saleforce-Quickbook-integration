/**
 * @class QuickBookTokenUtil
 * @description Utility class for managing QuickBooks Online OAuth 2.0 authentication tokens.
 *              Handles the full token lifecycle:
 *                - Generating the authorization URL to initiate the OAuth flow
 *                - Exchanging the authorization code for an access + refresh token
 *                - Validating whether the current access token is still valid
 *                - Refreshing an expired access token using the stored refresh token
 *              All token configuration (client ID, secret, URLs, etc.) is stored in
 *              the quickBook__mdt Custom Metadata Type under the 'QB_Token' record.
 */
public with sharing class QuickBookTokenUtil {

    /**
     * @method authorize
     * @description Constructs and returns the QuickBooks OAuth 2.0 authorization URL
     *              to initiate the OAuth flow. The user is redirected to this URL
     *              to grant access, after which QuickBooks redirects back to the
     *              configured Salesforce Visualforce page with an authorization code.
     *
     * @return PageReference  A redirect to the QuickBooks authorization URL on success,
     *                        or null if the metadata configuration record is not found
     *                        (an error message is added to the page in that case).
     */
    public PageReference authorize() {

        // ── Step 1: Load QB configuration from Custom Metadata ───────────────────────────
        quickBook__mdt config = quickBook__mdt.getInstance('QB_Token');

        if (config != null) {
            // ── Step 2: Build the Redirect URI ───────────────────────────────────────────
            // The redirect URI must match exactly what is registered in the QuickBooks
            // Developer Portal. It points back to the Salesforce Visualforce page that
            // will handle the authorization code callback.
            String redirect_Uri = System.Url.getOrgDomainUrl().toExternalForm()
                                + '/apex/' + config.PageName__c;
            System.debug('Redirect URL: ' + redirect_Uri);

            // ── Step 3: Construct the Authorization URL ───────────────────────────────────
            // Combines the base auth URL from metadata with required OAuth 2.0 parameters:
            //   - client_id:     Identifies this connected app to QuickBooks
            //   - response_type: Must be 'code' for the authorization code grant flow
            //   - scope:         Permissions requested (accounting, payments, OpenID profile data)
            //   - redirect_uri:  Where QuickBooks sends the user after authorization
            //   - state:         Used to prevent CSRF attacks; encodes the org ID + redirect URI
            String authUrl = config.Auth_Url__c
                            + '&client_id='     + config.Client_Id__c
                            + '&response_type=code'
                            + '&scope=com.intuit.quickbooks.accounting com.intuit.quickbooks.payment openid profile email phone address'
                            + '&redirect_uri='  + redirect_Uri
                            + '&state='         + UserInfo.getOrganizationId() + redirect_Uri;
            System.debug('Auth URL: ' + authUrl);

            // Redirect the user's browser to the QuickBooks authorization page
            return new PageReference(authUrl);

        } else {
            // Metadata record not found — cannot build the auth URL without configuration
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR,
                'Configuration not found. Please check the metadata record.'
            ));
            return null;
        }
    }


    /**
     * @method get_accessToken
     * @description Handles the OAuth 2.0 callback after the user has authorized access
     *              on the QuickBooks login page. Exchanges the short-lived authorization
     *              code (returned as a URL parameter) for a long-lived access token and
     *              refresh token, then persists both to the QB_Token metadata record
     *              for use in subsequent API callouts.
     *
     * @note This method is intended to be called from the Visualforce page that
     *       QuickBooks redirects back to after authorization. It reads the 'code'
     *       and 'realmId' parameters directly from the current page URL.
     */
    public void get_accessToken() {

        // ── Step 1: Load QB configuration from Custom Metadata ───────────────────────────
        quickBook__mdt config = quickBook__mdt.getInstance('QB_Token');

        if (config != null) {
            // ── Step 2: Extract Parameters from the Callback URL ─────────────────────────
            // QuickBooks appends these to the redirect URI after the user grants access:
            //   - code:    The one-time authorization code to exchange for tokens
            //   - realmId: The QuickBooks company ID this authorization is associated with
            String code    = ApexPages.currentPage().getParameters().get('code');
            String realmId = ApexPages.currentPage().getParameters().get('realmId');

            // ── Step 3: Build the Token Exchange HTTP Request ─────────────────────────────
            // QuickBooks token endpoint expects a POST with URL-encoded form data
            HttpRequest req = new HttpRequest();
            req.setMethod('POST');
            req.setHeader('content-type', 'application/x-www-form-urlencoded');
            req.setHeader('accept', 'application/json');
            req.setEndpoint(config.token_url__c);

            // The redirect_uri here must exactly match the one used in the authorize() step
            String redirect_Uri = System.Url.getOrgDomainUrl().toExternalForm()
                                + '/apex/' + config.PageName__c;
            System.debug('Redirect URL: ' + redirect_Uri);

            // Construct the request body with all required OAuth 2.0 token exchange parameters:
            //   - grant_type:    Must be 'authorization_code' for this flow
            //   - code:          The authorization code received in the callback
            //   - redirect_uri:  Must match the originally registered URI
            //   - client_id:     Identifies the connected app
            //   - client_secret: Authenticates the connected app server-side
            String tokenBody = 'grant_type=authorization_code'
                             + '&code='          + code
                             + '&redirect_uri='  + redirect_Uri
                             + '&client_id='     + config.Client_Id__c
                             + '&client_secret=' + config.Client_Secret__c;
            req.setBody(tokenBody);

            // ── Step 4: Execute the Token Exchange Callout ────────────────────────────────
            try {
                HttpResponse res = new Http().send(req);

                if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
                    // ── Success: Parse the Token Response ────────────────────────────────
                    Map<String, Object> tokenResponse =
                        (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

                    String  accessToken  = (String)  tokenResponse.get('access_token');
                    String  refreshToken = (String)  tokenResponse.get('refresh_token');
                    Integer expiresIn    = (Integer) tokenResponse.get('expires_in'); // Seconds until token expires

                    // ── Step 5: Persist Tokens to Custom Metadata ─────────────────────────
                    // Map the parsed token values to the metadata field API names
                    // NOTE: 'access_token__cc' below appears to be a typo — should be 'access_token__c'
                    // NOTE: 'expires_in__c' is being set to refreshToken instead of the expiry value
                    String fullName = 'quickBook.QB_Token';
                    String label    = 'QB_Token';

                    Map<String, Object> fieldWithValueMap = new Map<String, Object>();
                    fieldWithValueMap.put('access_token__cc',     accessToken);                        // BUG: likely typo, should be 'access_token__c'
                    fieldWithValueMap.put('refresh_token__c',     refreshToken);
                    fieldWithValueMap.put('expires_in_time__c',   System.now().addSeconds(expiresIn)); // Absolute expiry timestamp
                    fieldWithValueMap.put('expires_in__c',        refreshToken);                       // BUG: should store expiresIn (Integer), not refreshToken
                    fieldWithValueMap.put('realmId__c',           realmId);

                    // Deploy/update the QB_Token metadata record with the new token values
                    CreateUpdateMetadataUtils.createUpdateMetadata(fullName, label, fieldWithValueMap);
                    ApexPages.addMessage(new ApexPages.Message(
                        ApexPages.Severity.CONFIRM,
                        'Access token obtained and stored successfully.'
                    ));

                } else {
                    // Non-2xx response — log the failure details for debugging
                    System.debug('Failed to get access token. Status code: '
                                + res.getStatusCode() + ', Response body: ' + res.getBody());
                }

            } catch (Exception e) {
                // Handles unexpected runtime errors (e.g., JSON parsing failures)
                System.debug(e);
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, e.getMessage()));

            } catch (CalloutException ex) {
                // Handles HTTP-level errors (e.g., network timeout, unreachable endpoint)
                // NOTE: In Apex, CalloutException extends Exception, so this block
                //       will never be reached as-is — the Exception catch above fires first.
                //       Swap the order to catch CalloutException before Exception.
                System.debug(ex);
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, ex.getMessage()));
            }

        } else {
            // Metadata record not found — cannot proceed without API credentials
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR,
                'Configuration not found. Please check the metadata record.'
            ));
        }
    }


    /**
     * @method isValid
     * @description Checks whether the stored QuickBooks access token is still valid
     *              by comparing its expiry timestamp against the current system time.
     *
     * @param config  The QB_Token Custom Metadata record containing the token expiry time.
     * @return Boolean  true if the token has not yet expired, false if it has expired
     *                  and a refresh is needed before making API calls.
     */
    public static Boolean isValid(quickBook__mdt config) {
        Boolean isValid = true;

        // If the stored expiry timestamp is in the past, the token is no longer usable
        if (config.expires_in_time__c <= System.now()) {
            isValid = false;
        }

        return isValid;
    }


    /**
     * @method refreshToken
     * @description Requests a new access token from QuickBooks using the stored refresh token.
     *              Called automatically when isValid() returns false, so that API callouts
     *              can continue without requiring the user to re-authorize.
     *              The returned map is used both to update the in-memory token for the
     *              current request and to persist the new values back to Custom Metadata.
     *
     * @return Map<String, Object>  A field-value map of updated metadata fields
     *                              (access_token__c, refresh_token__c, expires_in_time__c, etc.)
     *                              ready to be passed to CreateUpdateMetadataUtils.
     *                              Returns an empty map if the refresh fails.
     *
     * @note  `config` is referenced but not declared as a parameter — this will cause
     *         a compile error. The config object must be passed in as a parameter,
     *         matching the signature expected by callers in QB_Customers and QB_Items.
     */
    public static Map<String, Object> refreshToken() {
        // Build the token refresh request body with required OAuth 2.0 parameters:
        //   - grant_type:     Must be 'refresh_token' for this flow
        //   - refresh_token:  The stored refresh token used to obtain a new access token
        //   - client_id:      Identifies the connected app
        //   - client_secret:  Authenticates the connected app server-side
        // NOTE: `config` is undefined here — add it as a method parameter to fix the compile error
        String tokenUrl    = config.token_url__c;
        String requestBody = 'grant_type=refresh_token'
                           + '&refresh_token=' + config.refresh_token__c
                           + '&client_id='     + config.Client_Id__c
                           + '&client_secret=' + config.Client_Secret__c;
        System.debug('Refresh Token Request Body: ' + requestBody);

        // Prepare the HTTP request using a shared callout utility
        HttpRequest httpReq = PS_CalloutUtils.prepareRequest(
            tokenUrl, 'POST', requestBody, 'application/json', 'application/x-www-form-urlencoded'
        );

        Map<String, Object> fieldWithValuesMap = new Map<String, Object>();

        try {
            HttpResponse httpRes = (new Http()).send(httpReq);

            if (httpRes.getStatusCode() == 200 || httpRes.getStatusCode() == 201) {
                // Parse the response and build the metadata field map
                // realmId is passed as empty string here since refresh does not change the company
                fieldWithValuesMap = prepareMetadata(httpRes.getBody(), '');
            } else {
                // Non-2xx response — log for debugging; return empty map to signal failure
                System.debug('Failed to refresh token. Status code: '
                            + httpRes.getStatusCode() + ', Response body: ' + httpRes.getBody());
            }

        } catch (System.CalloutException ex) {
            // Handles HTTP-level errors (e.g., timeout, DNS failure)
            // TODO: Add error logging or re-throw to notify the caller of the failure
        } catch (System.Exception ex) {
            // Handles unexpected runtime errors during the callout or response parsing
            // TODO: Add error logging or re-throw to notify the caller of the failure
        }

        // Returns the populated map on success, or an empty map if an error occurred
        return fieldWithValuesMap;
    }


    /**
     * @method prepareMetadata
     * @description Parses a raw QuickBooks token API response body and maps the returned
     *              token fields into a metadata field-value map, ready to be persisted
     *              to the QB_Token Custom Metadata record via CreateUpdateMetadataUtils.
     *              Used by both get_accessToken() and refreshToken() to avoid duplicating
     *              the parsing and mapping logic.
     *
     * @param requestBody  The raw JSON response body from the QuickBooks token endpoint.
     * @param realmId      The QuickBooks company (realm) ID. Pass a non-blank value when
     *                     calling from the initial authorization flow; pass an empty string
     *                     when refreshing (the realmId does not change on refresh).
     *
     * @return Map<String, Object>  A map of metadata field API names to their new values,
     *                              ready to be passed to CreateUpdateMetadataUtils.
     */
    public static Map<String, Object> prepareMetadata(String requestBody, String realmId) {
        // Parse the raw JSON response into a generic map
        Map<String, Object> responseMap =
            (Map<String, Object>) JSON.deserializeUntyped(requestBody);

        // Extract the relevant token fields from the parsed response
        String  access_token  = (String)  responseMap.get('access_token');
        String  refresh_token = (String)  responseMap.get('refresh_token');
        Integer expires_in    = (Integer) responseMap.get('expires_in'); // Seconds until token expires

        // Build the metadata field map with the new token values
        Map<String, Object> fieldWithValuesMap = new Map<String, Object>();
        fieldWithValuesMap.put('access_token__c',   access_token);
        fieldWithValuesMap.put('expires_in__c',     expires_in);
        fieldWithValuesMap.put('expires_in_time__c', System.now().addSeconds(expires_in)); // Absolute expiry datetime
        fieldWithValuesMap.put('refresh_token__c',  refresh_token);

        // Only update the realmId field if a non-blank value was provided
        // (realmId is only set during initial authorization, not during token refresh)
        if (!String.isBlank(realmId)) {
            fieldWithValuesMap.put('realmId__c', realmId);
        }

        return fieldWithValuesMap;
    }
}
