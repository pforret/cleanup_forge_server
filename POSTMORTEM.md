  Post-Mortem: Web Server Compromise                                                                                                                
                                                                                                                                                    
  Date                                                                                                                                              
                                                                                                                                                    
  2026-01-31                                                                                                                                        
                                                                                                                                                    
  Summary                                                                                                                                           
                                                                                                                                                    
  A Laravel Forge-managed DigitalOcean VPS was compromised. The attacker deployed multiple PHP webshells across the application's public directory, 
  planted a backdoor in Laravel's storage directory, and established persistent access via a Perl IRC botnet agent running on a cron schedule.      
                                                                                                                                                    
  Attack Description                                                                                                                                
                                                                                                                                                    
  Classification                                                                                                                                    
                                                                                                                                                    
  PHP webshell deployment + Perl IRC bot persistence — a common automated attack pattern targeting PHP web applications.                            
                                                                                                                                                    
  What Was Found                                                                                                                                    
  ┌──────────────────────┬──────────────────────────────────┬─────────────────────────────────────────────────┐                                     
  │      Component       │             Location             │                     Purpose                     │                                     
  ├──────────────────────┼──────────────────────────────────┼─────────────────────────────────────────────────┤                                     
  │ 14+ PHP webshells    │ public/*.php                     │ Remote code execution via browser               │                                     
  ├──────────────────────┼──────────────────────────────────┼─────────────────────────────────────────────────┤                                     
  │ Encoded PHP backdoor │ storage/framework/sessions/s.php │ Hidden webshell outside git-tracked directories │                                     
  ├──────────────────────┼──────────────────────────────────┼─────────────────────────────────────────────────┤                                     
  │ Perl IRC bot         │ /var/tmp/DHrLgBEnK               │ Persistent C2 (command & control) communication │                                     
  ├──────────────────────┼──────────────────────────────────┼─────────────────────────────────────────────────┤                                     
  │ Crontab entries      │ forge user crontab               │ Re-launch IRC bot every 5–6 minutes             │                                     
  └──────────────────────┴──────────────────────────────────┴─────────────────────────────────────────────────┘                                     
  Webshell Details                                                                                                                                  
                                                                                                                                                    
  - Password-protected shells (defaults.php) — SHA-256 gated login form leading to a full shell interface                                           
  - Obfuscated shells (f35.php) — multi-layer encoding using gzuncompress, str_replace, eval, with the payload appended as binary data after        
  __halt_compiler()                                                                                                                                 
  - Zeura-encoded shell (storage/framework/sessions/s.php) — uuencoded and base64-wrapped with SHA-1 integrity checks to prevent tampering          
  - Hex-named shells (1d5efca38c.php, etc.) — .php + .txt pairs where the .txt files contained payloads disguised as WordPress boilerplate comments 
                                                                                                                                                    
  Persistence Mechanism                                                                                                                             
                                                                                                                                                    
  The attacker installed a Perl IRC bot in /var/tmp/DHrLgBEnK with two crontab entries under the forge user:                                        
                                                                                                                                                    
  */5 * * * * /usr/bin/perl /var/tmp/DHrLgBEnK >/dev/null 2>&1                                                                                      
  */6 * * * * perl /var/tmp/DHrLgBEnK >/dev/null 2>&1                                                                                               
                                                                                                                                                    
  The bot used uuencoded data and hex substitution to hide IRC server addresses. It connected to command-and-control servers, allowing the attacker 
  to issue commands remotely. The dual cron entries (5-minute and 6-minute intervals) provided redundancy.                                          
                                                                                                                                                    
  Attack Chain (Probable)                                                                                                                           
                                                                                                                                                    
  1. Initial access — exploit of a web-facing vulnerability (exact vector not confirmed; APP_DEBUG was false, ruling out CVE-2021-3129 Ignition RCE)
  2. Webshell deployment — multiple PHP files dropped in public/ for redundant access                                                               
  3. Privilege within app — webshell used to read .env (database credentials, API keys, APP_KEY)                                                    
  4. Storage backdoor — additional shell placed in storage/framework/sessions/ to survive git clean of public/                                      
  5. Persistent access — Perl IRC bot installed in /var/tmp/ with crontab entries for automatic restart                                             
                                                                                                                                                    
  Detection                                                                                                                                         
                                                                                                                                                    
  How It Was Discovered                                                                                                                             
                                                                                                                                                    
  Untracked files with random hexadecimal names appeared in git status output in the public/ directory.                                             
                                                                                                                                                    
  Detection Methods                                                                                                                                 
                                                                                                                                                    
  - git status — untracked files with hex names in public/ are an immediate red flag                                                                
  - grep -rl "eval\|base64_decode\|gzinflate\|shell_exec" in web roots — identifies obfuscated PHP webshells                                        
  - find storage/ -name "*.php" -not -path "*/views/*" — PHP files in storage/framework/sessions/ are never legitimate                              
  - crontab -l — entries referencing /var/tmp, /dev/shm, or /tmp are almost always malicious                                                        
  - find /var/tmp /dev/shm -type f — legitimate applications rarely store files here                                                                
  - Nginx access logs — requests to non-index.php PHP files in public/                                                                              
                                                                                                                                                    
  Signatures to Monitor                                                                                                                             
                                                                                                                                                    
  # Webshell indicators in PHP files                                                                                                                
  eval(base64_decode(                                                                                                                               
  eval(gzinflate(                                                                                                                                   
  eval(gzuncompress(                                                                                                                                
  eval(str_rot13(                                                                                                                                   
  system($_GET                                                                                                                                      
  system($_POST                                                                                                                                     
  shell_exec($_REQUEST                                                                                                                              
  __halt_compiler()                                                                                                                                 
  zeura.com                                                                                                                                         
                                                                                                                                                    
  # Filesystem indicators                                                                                                                           
  PHP files in storage/framework/sessions/                                                                                                          
  PHP files in public/ not named index.php                                                                                                          
  Perl/Python scripts in /var/tmp/ or /dev/shm/                                                                                                     
                                                                                                                                                    
  Remediation                                                                                                                                       
                                                                                                                                                    
  Immediate Actions Taken                                                                                                                           
                                                                                                                                                    
  1. Webshells removed — git reset --hard and git clean -df on all site repositories                                                                
  2. Storage backdoor deleted — rm storage/framework/sessions/s.php                                                                                 
  3. Crontab cleared — crontab -r for the forge user                                                                                                
  4. IRC bot killed and deleted — pkill -f DHrLgBEnK && rm /var/tmp/DHrLgBEnK                                                                       
  5. Temp directories cleaned — all forge-owned files removed from /var/tmp/ and /dev/shm/                                                          
  6. SSH keys verified — no unauthorized keys in ~/.ssh/authorized_keys                                                                             
  7. Cleanup script deployed — automated scan and clean across all sites on the server                                                              
                                                                                                                                                    
  Still Required                                                                                                                                    
                                                                                                                                                    
  - Rotate all .env credentials on every site (DB passwords, API keys, SMTP, third-party tokens)                                                    
  - Regenerate APP_KEY on every Laravel site (php artisan key:generate)                                                                             
  - Rotate database passwords at the server level                                                                                                   
  - Audit databases for injected admin users or modified records                                                                                    
  - Analyze nginx access logs to identify the initial entry vector                                                                                  
  - Update Laravel and all Composer dependencies to latest versions                                                                                 
  - Consider full server rebuild via Forge (recommended — cannot guarantee all backdoors were found)                                                
                                                                                                                                                    
  Recommendations                                                                                                                                   
                                                                                                                                                    
  1. Rebuild the server — the only way to guarantee a clean system is to provision a fresh droplet, deploy from git, and use new credentials        
  2. File integrity monitoring — deploy a tool like aide or use inotifywait to alert on new PHP files in public/ and storage/                       
  3. Disable PHP execution in upload/storage directories via nginx:                                                                                 
  location ~* /storage/.*\.php$ { deny all; }                                                                                                       
  location ~* /public/(uploads|files|images)/.*\.php$ { deny all; }                                                                                 
  4. Keep dependencies updated — subscribe to Laravel security advisories                                                                           
  5. Restrict outbound connections — use UFW to block outbound IRC ports (6667, 6697) and limit outbound to only required services                  
  6. Regular git status checks — a cron job that alerts on untracked files in web roots                                                             
  7. Enable Laravel Forge security features — automatic security updates, SSH key-only authentication                                               
                                                                                                                                                    
  Unresolved Questions                                                                                                                              
                                                                                                                                                    
  - What was the initial entry vector? Nginx access logs need analysis to determine how the first webshell was uploaded.                            
  - How long was the attacker present? Earliest file creation timestamps and log entries need correlation.                                          
  - Was any data exfiltrated? Database access was possible via .env credentials.                                                                    
  - Were other servers or services accessed using credentials from .env?                                                                            

