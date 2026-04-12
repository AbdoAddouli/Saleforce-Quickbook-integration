# Saleforce-Quickbook-integration

# Salesforce ↔ QuickBooks Online Integration

A native Salesforce integration that connects your Salesforce org to **QuickBooks Online** using the **QuickBooks REST API** and **OAuth 2.0**. The integration allows you to sync Salesforce records (Products, Customers, etc.) directly to QuickBooks without any middleware or third-party tools.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Custom Metadata Configuration](#custom-metadata-configuration)
- [Apex Classes](#apex-classes)
- [OAuth 2.0 Flow](#oauth-20-flow)
- [Setup & Installation](#setup--installation)
- [Usage](#usage)
- [Known Issues & Bugs Fixed](#known-issues--bugs-fixed)
- [Roadmap](#roadmap)

---

## Overview

This integration is built entirely in **Apex** on the Salesforce platform and uses:

- **QuickBooks Online REST API v3** for creating and managing records
- **OAuth 2.0 Authorization Code Grant** for secure authentication
- **Custom Metadata Types** to store and manage API credentials and configuration without hardcoding sensitive values
- **Salesforce Custom Metadata Deployment API** (`CreateUpdateMetadataUtils`) to dynamically update tokens at runtime

### Supported Operations

| Salesforce Object | QuickBooks Entity | Direction        |
|-------------------|-------------------|------------------|
| `Product2`        | Item              | Salesforce → QB  |
| Account / Contact | Customer          | Salesforce → QB  |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                          Salesforce Org                             │
│                                                                     │
│  ┌──────────────┐    ┌──────────────────┐    ┌───────────────────┐  │
│  │  QB_Items    │    │  QB_Customers    │    │QuickBookTokenUtil │  │
│  │  (Apex)      │───▶│  (Apex)          │───▶│  (Apex)          │  │
│  └──────────────┘    └──────────────────┘    └───────────────────┘  │
│          │                    │                        │             │
│          └────────────────────┴────────────────────────┘            │
│                               │                                     │
│                    ┌──────────▼──────────┐                          │
│                    │  quickBook__mdt     │                          │
│                    │  (Custom Metadata)  │                          │
│                    └──────────┬──────────┘                          │
└───────────────────────────────┼─────────────────────────────────────┘
                                │ HTTP Callouts
                                ▼
                   ┌────────────────────────┐
                   │  QuickBooks Online     │
                   │  REST API v3           │
                   │  (api.intuit.com)      │
                   └────────────────────────┘
```

---

## Custom Metadata Configuration

All API credentials and configuration are stored in a **Custom Metadata Type** called **`quickBook__mdt`**. This avoids hardcoding sensitive values in Apex code and allows configuration to be deployed across environments (Sandbox / Production) without code changes.

### Metadata Type: `quickBook__mdt`

> **Record Name used by this integration:** `QB_Token`

Below is the full list of custom fields defined on the metadata type:

| Field Label          | API Name                  | Data Type              | Description                                                             |
|----------------------|---------------------------|------------------------|-------------------------------------------------------------------------|
| `access_token`       | `access_token__c`         | Long Text Area (32768) | The OAuth 2.0 access token used to authenticate API requests            |
| `auth_url`           | `auth_url__c`             | URL(255)               | The QuickBooks authorization endpoint URL                               |
| `Client Id`          | `Client_Id__c`            | Text(255)              | The OAuth 2.0 Client ID from the Intuit Developer Portal                |
| `Client Secret`      | `Client_Secret__c`        | Text(255)              | The OAuth 2.0 Client Secret from the Intuit Developer Portal            |
| `Company Info`       | `Company_Info__c`         | URL(255)               | QuickBooks Company Info API endpoint                                    |
| `Create Bill`        | `Create_Bill__c`          | URL(255)               | QuickBooks API endpoint for creating Bills                              |
| `Create Customer`    | `Create_Customer__c`      | URL(255)               | QuickBooks API endpoint for creating Customers                          |
| `Create Estimate`    | `Create_Estimate__c`      | URL(255)               | QuickBooks API endpoint for creating Estimates                          |
| `Create Invoice`     | `Create_Invoice__c`       | URL(255)               | QuickBooks API endpoint for creating Invoices                           |
| `Create Payment`     | `Create_Payment__c`       | URL(255)               | QuickBooks API endpoint for creating Payments                           |
| `Create Vendor`      | `Create_Vendor__c`        | URL(255)               | QuickBooks API endpoint for creating Vendors                            |
| `Customer Url`       | `Customer_Url__c`         | URL(255)               | Base URL for Customer operations                                        |
| `Environment`        | `Environment__c`          | Picklist               | `Production` or `Sandbox` — controls which base URL is used             |
| `expires_in`         | `expires_in__c`           | Number(10, 0)          | Access token lifetime in seconds (typically 3600)                       |
| `expires in time`    | `expires_in_time__c`      | Date/Time              | Absolute datetime when the current access token expires                 |
| `minorversion`       | `minorversion__c`         | Text(10)               | QuickBooks API minor version to append to all requests                  |
| `PageName`           | `PageName__c`             | Text(255)              | Name of the Salesforce Visualforce page used as the OAuth callback      |
| `Production Base URL`| `Production_Base_URL__c`  | URL(255)               | Base URL for QuickBooks Production API (`https://quickbooks.api.intuit.com`) |
| `realmId`            | `realmId__c`              | Text(255)              | The QuickBooks Company ID, returned after OAuth authorization           |
| `refresh_token`      | `refresh_token__c`        | Long Text Area (32768) | The OAuth 2.0 refresh token used to obtain new access tokens            |
| `Sandbox Base URL`   | `Sandbox_Base_URL__c`     | URL(255)               | Base URL for QuickBooks Sandbox API (`https://sandbox-quickbooks.api.intuit.com`) |
| `token_type`         | `token_type__c`           | Text(255)              | Token type returned by QuickBooks (typically `Bearer`)                  |
| `token_url`          | `token_url__c`            | URL(255)               | The QuickBooks token exchange endpoint URL                              |

> ⚠️ **Important:** The `Client_Secret__c` and `access_token__c` fields contain sensitive credentials. Ensure that field-level security is restricted to System Administrators only.

---

## Apex Classes

### `QuickBookTokenUtil`
Manages the full OAuth 2.0 token lifecycle:
- `authorize()` — Builds and returns the QuickBooks authorization URL to initiate the OAuth flow
- `get_accessToken()` — Exchanges the authorization code for access + refresh tokens and stores them in metadata
- `isValid(config)` — Checks if the current access token is still valid based on the `expires_in_time__c` field
- `refreshToken(config)` — Requests a new access token using the stored refresh token
- `prepareMetadata(body, realmId)` — Parses a token response and returns a field-value map ready for metadata deployment

### `QB_Customers`
Handles customer synchronization from Salesforce to QuickBooks:
- `createCustomer(customer)` — Sends a `QBCustomerInput` object to the QuickBooks Customers API
- `testCreateCustomer()` — Developer utility method for manually testing the customer creation flow

### `QB_Items`
Handles product/item synchronization from Salesforce to QuickBooks:
- `createItem(item, productRecord)` — Sends a `QB_ItemInput` object to the QuickBooks Items API and updates the `Product2` record with the returned QB Item ID
- `testCreateItem()` — Queries all unsynced `Product2` records and syncs them to QuickBooks in bulk

---

## OAuth 2.0 Flow

This integration uses the **Authorization Code Grant** flow:

```
1. Admin clicks "Connect to QuickBooks" on the Visualforce page
        │
        ▼
2. QuickBookTokenUtil.authorize() builds the QB authorization URL
        │
        ▼
3. User is redirected to QuickBooks login and grants access
        │
        ▼
4. QuickBooks redirects back to the Salesforce VF page with ?code=...&realmId=...
        │
        ▼
5. QuickBookTokenUtil.get_accessToken() exchanges the code for tokens
        │
        ▼
6. Tokens (access_token, refresh_token, expires_in_time) are saved to quickBook__mdt
        │
        ▼
7. All subsequent API calls use the stored access_token
   — If expired, refreshToken() is called automatically before the callout
```

---

## Setup & Installation

### Prerequisites
- Salesforce org (Developer Edition, Sandbox, or Production)
- A QuickBooks Online account with an app created in the [Intuit Developer Portal](https://developer.intuit.com)
- The Salesforce org's domain URL added as a **Redirect URI** in the Intuit Developer Portal

### Steps

1. **Deploy the metadata and Apex classes** to your org using Salesforce CLI or Change Sets:
   ```bash
   sf project deploy start --source-dir force-app
   ```

2. **Create the `QB_Token` Custom Metadata record** via Setup → Custom Metadata Types → `quickBook__mdt` → Manage Records → New:
   - Set `Environment__c` to `Sandbox` or `Production`
   - Set `Client_Id__c` and `Client_Secret__c` from the Intuit Developer Portal
   - Set `auth_url__c` to `https://appcenter.intuit.com/connect/oauth2`
   - Set `token_url__c` to `https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer`
   - Set `Production_Base_URL__c` to `https://quickbooks.api.intuit.com`
   - Set `Sandbox_Base_URL__c` to `https://sandbox-quickbooks.api.intuit.com`
   - Set `PageName__c` to the name of your OAuth callback Visualforce page
   - Set `minorversion__c` to `65` (or your target minor version)

3. **Add Remote Site Settings** in Setup → Remote Site Settings:
   - `https://appcenter.intuit.com`
   - `https://oauth.platform.intuit.com`
   - `https://quickbooks.api.intuit.com`
   - `https://sandbox-quickbooks.api.intuit.com`

4. **Navigate to the Visualforce callback page** and click **Authorize** to complete the OAuth flow. Tokens will be automatically stored in the metadata record.

5. **Add the `QBExternalId__c` custom field** (Text, External ID) to the `Product2` object to store the QuickBooks Item ID.

---

## Usage

### Sync a single Product to QuickBooks
```apex
QB_ItemInput item = new QB_ItemInput();
item.Name = 'My Product';
// ... populate other fields

Product2 product = [SELECT Id, Name FROM Product2 WHERE Id = :someId];
QB_Items.createItem(item, product);
update product;
```

### Bulk sync all unsynced Products
```apex
QB_Items.testCreateItem();
```

### Create a Customer in QuickBooks
```apex
QB_Customers.testCreateCustomer(); // uses hardcoded test data
// or build your own QBCustomerInput and call:
QB_Customers.createCustomer(myCustomerInput);
```

---

## Known Issues & Bugs Fixed

The following bugs were identified and corrected during development:

| Class | Bug | Fix |
|---|---|---|
| `QuickBookTokenUtil.get_accessToken()` | `access_token__cc` typo in field name | Changed to `access_token__c` |
| `QuickBookTokenUtil.get_accessToken()` | `expires_in__c` was set to `refreshToken` instead of the expiry integer | Corrected to store `expiresIn` |
| `QuickBookTokenUtil.get_accessToken()` | `CalloutException` caught after `Exception` so it was never reached | Swapped catch block order |
| `QuickBookTokenUtil.refreshToken()` | `config` used but not declared as a parameter | Added `config` as method parameter |
| `QB_Customers.createCustomer()` | SOQL `FROM quickBook__md` missing trailing `t` | Corrected to `quickBook__mdt` |
| `QB_Customers` / `QB_Items` | `String accessToken` re-declared inside `if` block, shadowing outer variable | Removed `String` keyword to reassign existing variable |
| `QB_Items.createItem()` | `productId` used before being extracted from `itemMap` | Added `String productId = (String) itemMap.get('Id')` |
| `QB_Customers` / `QB_Items` | `fieldWithValueMap` (no `s`) typo in metadata update call | Corrected to `fieldWithValuesMap` |

---

## Roadmap

- [ ] Add support for QuickBooks **Invoices** synced from Salesforce Opportunities
- [ ] Add support for **Vendors** synced from Salesforce Accounts
- [ ] Add support for **Bills** synced from Salesforce records
- [ ] Implement platform event or trigger-based real-time sync
- [ ] Add proper Apex test classes with mock HTTP callouts
- [ ] Add error logging to a custom `QB_Sync_Log__c` object for audit trails
- [ ] Support token auto-refresh via Scheduled Apex before expiry

---

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

---

## License

This project is licensed under the MIT License.
