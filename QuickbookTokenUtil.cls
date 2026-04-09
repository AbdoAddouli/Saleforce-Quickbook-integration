public with sharing class QuickBookTokenUtil {
    //prepare the auth URL 
    public PageReference authorize(){
        //get the config from metadata
        quickBook__mdt config = quickBook__mdt.getInstance('QB_Token');
        if(config != null){
            String redirect_Uri = System.Url.getOrgDomainUrl().toExternalForm() + '/apex/' + config.PageName__c;
            System.System.debug('Redirect URL: ' + redirect_Uri);
            String authUrl = config.Auth_Url__c + '&client_id=' + 
                            config.Client_Id__c + '&response_type=code'+ '&scope=com.intuit.quickbooks.accounting com.intuit.quickbooks.payment openid profile email phone address' + '&redirect_uri=' + 
                            redirect_Uri + '&state=' + UserInfo.getOrganizationId() + redirect_Uri;
            System.debug('Auth URL: ' + authUrl);
            return new PageReference(authUrl);
        }else {
            //show the error message if config is not found
            ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'Configuration not found. Please check the metadata record.'));
            return null;
        }

        
    }
    
    //get the Access token and Store it in metadata
    public void get_accessToken(){
        quickBook__mdt config = quickBook__mdt.getInstance('QB_Token');
        if(config != null){
            String code = ApexPages.currentPage().getParameters().get('code');
            String realmId = ApexPages.currentPage().getParameters().get('realmId');
            HttpRequest req = new HttpRequest();
            req.setMethod('POST');
            req.setHeader('content-type', 'application/x-www-form-urlencoded');
            req.setHeader('accept', 'application/json');
            req.setEndpoint(config.token_url__c);

            /*
            grant_type=authorization_code&
            code=L3114709614564VSU8JSEiPkXx1xhV8D9mv4xbv6sZJycibMUI&
            redirect_uri=https://www.mydemoapp.com/oauth-redirect;
            */
            String redirect_Uri = System.Url.getOrgDomainUrl().toExternalForm() + '/apex/' + config.PageName__c;
            System.System.debug('Redirect URL: ' + redirect_Uri);

            String tokenBody = 'grant_type=authorization_code&code=' + code + '&redirect_uri=' + redirect_Uri + '&client_id=' + config.Client_Id__c + '&client_secret=' + config.Client_Secret__c;
            req.setBody(tokenBody);
            try {
                HttpResponse res = new Http().send(req);
                if (res.getStatusCode() == 200 ||res.getStatusCode() == 201 ) {
                    //parse the Response
                    Map<String,Object> tokenResponse = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                    String accessToken = (String) tokenResponse.get('access_token');
                    String refreshToken = (String) tokenResponse.get('refresh_token');
                    Integer expiresIn = (Integer) tokenResponse.get('expires_in');

                    //map the response to the metadata
                    String fullName = 'quickBook.QB_Token';
                    String label = 'QB_Token';
                    Map<String, Object> fieldWithValueMap = new Map<String, Object>();
                    fieldWithValueMap.put('access_token__cc', accessToken);
                    fieldWithValueMap.put('refresh_token__c', refreshToken);
                    fieldWithValueMap.put('expires_in_time__c', System.now().addSeconds(expiresIn));
                    fieldWithValueMap.put('expires_in__c', refreshToken);
                    fieldWithValueMap.put('realmId__c', realmId);

                    //Deploy/update metadata
                    CreateUpdateMetadataUtils.createUpdateMetadata(fullName, label, fieldWithValueMap);
                    ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.CONFIRM, 'Access token obtained and stored successfully.'));
                    
                }else{
                    System.debug('Failed to get access token. Status code: ' + res.getStatusCode() + ', Response body: ' + res.getBody());
                }
                
            } catch (Exception e) {
                System.debug(e);
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, e.getMessage()));
                
            } catch (CalloutException ex) {
                System.debug(ex);
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, ex.getMessage()));

            }


        }else {
            //show the error message if config is not found
            ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'Configuration not found. Please check the metadata record.'));
        }
        
    }

    public static Boolean isValid(quickBook__mdt config){
        Boolean isValid  =true;
        if(config.expires_in_time__c == System.now() ){
            isValid = false;
        }
        return isValid;
    }

    public static Map<String, Object> refreshToken(){
        String tokenUrl = config.token_url__c;
        String requestBody = 'grant_type=refresh_token&refresh_token=' + config.refresh_token__c + 
                            '&client_id=' + config.Client_Id__c + '&client_secret=' + config.Client_Secret__c;
        System.debug('Refresh Token Request Body: ' + requestBody);
        HttpRequest httpReq = PS_CalloutUtils.prepareRequest(tokenUrl,'POST',requestBody,'application/json', 'application/x-www-form-urlencoded');
        Map<String, Object> fieldWithValuesMap = new Map<String, Object>();
        try{
            HttpResponse httpRes = (new Http()).send(httpReq);
            if(httpRes.getStatusCode() == 200 || httpRes.getStatusCode() == 201 ){
                fieldWithValuesMap = prepareMetadata(httpRes.getBody(),'');
            }else{
                System.debug('Failed to refresh token. Status code: ' + httpRes.getStatusCode() + ', Response body: ' + httpRes.getBody());
            }    
        }catch(System.CalloutException ex){

        }catch(System.Exception ex){

        }
        return fieldWithValuesMap;
    }

    public static Map<String, Object> prepareMetadata(String requestBody, String realmId){
        Map<String, Object> responseMap = (Map<String, Object>)JSON.deserializeUntyped(requestBody);
        String access_token  = (String)responseMap.get('access_token');
        String refresh_token = (String)responseMap.get('refresh_token');
        Integer expires_in   = (Integer)responseMap.get('expires_in');

        Map<String, Object> fieldWithValuesMap = new Map<String, Object>();
        fieldWithValuesMap.put('access_token__c', access_token);
        fieldWithValuesMap.put('expires_in__c',expires_in);
        fieldWithValuesMap.put('expires_in_time__c', System.now().addSeconds(expires_in) );
        fieldWithValuesMap.put('refresh_token__c', refresh_token);
        if(!String.isBlank(realmId)){
            fieldWithValuesMap.put('realmId__c', realmId);
        }
        return responseMap;
    }
}
