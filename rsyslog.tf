data "template_file" "cloud-config" {
  template = <<YAML
#cloud-config
runcmd:
  
 - yum install rsyslog 



 - firewall-cmd --add-port=514/tcp --permanent

 - firewall-cmd --add-port=514/tcp 

 - firewall-cmd --add-port=514/udp --permanent

 - firewall-cmd --add-port=514/udp

 
 - mkdir /var/log/deployment
 - touch /var/log/OCI/deployment.log
 - echo $HOSTNAME >> /var/log/OCI/deployment.log 
 - echo "# rsyslog configuration file

# For more information see /usr/share/doc/rsyslog-*/rsyslog_conf.html
# or latest version online at http://www.rsyslog.com/doc/rsyslog_conf.html 
# If you experience problems, see http://www.rsyslog.com/doc/troubleshoot.html

#### MODULES ####

module(load="imuxsock"    # provides support for local system logging (e.g. via logger command)
      SysSock.Use="on") # Turn off message reception via local log socket; 
#                          # local messages are retrieved through imjournal now.
module(load="imjournal"             # provides access to the systemd journal
       StateFile="imjournal.state") # File to store the position in the journal
#module(load="imklog") # reads kernel messages (the same are read from journald)
#module(load="immark") # provides --MARK-- message capability

# Provides UDP syslog reception
# for parameters see http://www.rsyslog.com/doc/imudp.html
#module(load="imudp") # needs to be done just once
#input(type="imudp" port="514")

# Provides TCP syslog reception
# for parameters see http://www.rsyslog.com/doc/imtcp.html
#module(load="imtcp") # needs to be done just once
#input(type="imtcp" port="514")

#### GLOBAL DIRECTIVES ####

# Where to place auxiliary files
global(workDirectory="/var/lib/rsyslog")

# Use default timestamp format
module(load="builtin:omfile" Template="RSYSLOG_TraditionalFileFormat")

# Include all config files in /etc/rsyslog.d/
include(file="/etc/rsyslog.d/*.conf" mode="optional")


        # Log cron stuff
cron.*                                                  /var/log/cron

# Everybody gets emergency messages
*.emerg                                                 :omusrmsg:*

# Save news errors of level crit and higher in a special file.
uucp,news.crit                                          /var/log/spooler

# Save boot messages also to boot.log
local7.*                                                /var/log/boot.log" > /etc/rsyslog.conf
local5.*                                                /var/log/OCI/deployment.log
*.*    @@rsyslog:514" > /etc/rsyslog.conf


 - systemctl enable --now rsyslog



 #- if $? = 0 find way to test exit then run 
 - echo "Instantiation of Master Rsyslog Server successfull!" >> /var/log/OCI/deployment.log

YAML
}



	


