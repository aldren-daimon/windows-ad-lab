# Ticket 02 – New PC can't join the domain

| | |
|---|---|
| Reported by | IT (new laptop setup) |
| Symptom | "An Active Directory Domain Controller for the domain dre.lab could not be contacted." |
| Priority | Medium |

## How I reproduced it
On CLIENT01, I set a static DNS server of 8.8.8.8, then tried to join `dre.lab`.

## Investigation
```powershell
ipconfig /all            # DNS Servers: 8.8.8.8  <- wrong
nslookup dre.lab         # fails: public DNS doesn't know my internal domain
Test-NetConnection 192.168.10.10 -Port 389   # DC reachable on LDAP, so network is fine
```

![DNS wrong](../screenshots/t02-dns-wrong.png)

## Root cause
Clients find domain controllers through DNS (SRV records in the `dre.lab` zone). With public DNS, the client can't find the DC even though the network works.

## Fix
```powershell
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ResetServerAddresses   # back to DHCP (DNS 192.168.10.10)
ipconfig /flushdns
nslookup dre.lab          # now answers from 192.168.10.10
Add-Computer -DomainName dre.lab -Credential DRE\Administrator -Restart
```

## Lesson
Domain PCs must use the domain controller for DNS. The DC forwards internet lookups itself.
