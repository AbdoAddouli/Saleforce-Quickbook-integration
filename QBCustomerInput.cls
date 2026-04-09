public with sharing class QBCustomerInput{
	public String FullyQualifiedName;	
	public PrimaryEmailAddr PrimaryEmailAddr;
	public String DisplayName;	
	public String Suffix;	
	public String Title;	
	public String MiddleName;	
	public String Notes;	
	public String FamilyName;	
	public PrimaryPhone PrimaryPhone;
	public String CompanyName;	
	public BillAddr BillAddr;
	public String GivenName;	
	class PrimaryEmailAddr {
		public String Address;	
	}
	public class PrimaryPhone {
		public String FreeFormNumber;	
	}
	public class BillAddr {
		public String CountrySubDivisionCode;	
		public String City;	
		public String PostalCode;	
		public String Line1;	
		public String Country;	
	}
	public static QBCustomerInput parse(String json){
		return (QBCustomerInput) System.JSON.deserialize(json, QBCustomerInput.class);
	}

	
}
