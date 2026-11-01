;
; BIND data file for local loopback interface
;
$TTL	604800
@	IN	SOA	ns1.example.com root.ns1.example.com. (
			      5		; Serial
			 604800		; Refresh
			  86400		; Retry
			2419200		; Expire
			 604800 )	; Negative Cache TTL
;
@	IN	NS	ns1.example.com.
@	IN	A	127.0.0.1
@	IN	AAAA	::1
ns1          IN      A       10.0.0.225
nas        IN      A       10.0.0.225