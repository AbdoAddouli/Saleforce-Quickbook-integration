
public with sharing class QBCustomerInput{
	public String FullyQualifiedName;	//{{$randomCompanyName}}
	public cls_PrimaryEmailAddr PrimaryEmailAddr;
	public String DisplayName;	//{{$randomCompanyName}}
	public String Suffix;	//Jr
	public String Title;	//Mr
	public String MiddleName;	//B
	public String Notes;	//Here are other details.
	public String FamilyName;	//King
	public cls_PrimaryPhone PrimaryPhone;
	public String CompanyName;	//{{$randomCompanyName}}
	public cls_BillAddr BillAddr;
	public String GivenName;	//James
	class cls_PrimaryEmailAddr {
		public String Address;	//{{$randomEmail}}
	}
	class cls_PrimaryPhone {
		public String FreeFormNumber;	//(555) 555-5555
	}
	class cls_BillAddr {
		public String CountrySubDivisionCode;	//CA
		public String City;	//Mountain View
		public String PostalCode;	//94042
		public String Line1;	//123 Main Street
		public String Country;	//USA
	}
	public static QBCustomerInput parse(String json){
		return (QBCustomerInput) System.JSON.deserialize(json, QBCustomerInput.class);
	}

	static testMethod void testParse() {
		String json=		'{'+
		'    "FullyQualifiedName": "{{$randomCompanyName}}",'+
		'    "PrimaryEmailAddr": {'+
		'        "Address": "{{$randomEmail}}"'+
		'    },'+
		'    "DisplayName": "{{$randomCompanyName}}",'+
		'    "Suffix": "Jr",'+
		'    "Title": "Mr",'+
		'    "MiddleName": "B",'+
		'    "Notes": "Here are other details.",'+
		'    "FamilyName": "King",'+
		'    "PrimaryPhone": {'+
		'        "FreeFormNumber": "(555) 555-5555"'+
		'    },'+
		'    "CompanyName": "{{$randomCompanyName}}",'+
		'    "BillAddr": {'+
		'        "CountrySubDivisionCode": "CA",'+
		'        "City": "Mountain View",'+
		'        "PostalCode": "94042",'+
		'        "Line1": "123 Main Street",'+
		'        "Country": "USA"'+
		'    },'+
		'    "GivenName": "James"'+
		'}';
		QBCustomerInput obj = parse(json);
		System.assert(obj != null);
	}
}
