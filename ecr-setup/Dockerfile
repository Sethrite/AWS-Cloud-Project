# Using the Amazon Linux image
FROM amazonlinux:2023

# Put Docker in a bash terminal instead of sh for RUN commands
SHELL ["/bin/bash", "-c"]

# Run updates, then install common commands and functionality
RUN dnf update -y
RUN dnf install -y shadow-utils tar gzip procps-ng util-linux nano vim-minimal iproute iputils nmap wget jq openssh-server sudo
RUN dnf clean all

# Generate SSH host keys (For internal ssh - this will help to generate logs)
RUN ssh-keygen -A && mkdir -p /var/run/sshd

# Run the install for metasploit specifically
RUN curl https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb > msfinstall && \
        chmod 755 msfinstall && \
        ./msfinstall && \
        rm msfinstall

# Create a Windows-style environment for a list of users
RUN for user in mark karma lily erik ned; do \
        useradd -m -s /bin/bash -G wheel "$user" && \
        mkdir -p /home/"$user"/Desktop /home/"$user"/Downloads /home/"$user"/Documents /home/"$user"/Pictures /home/"$user"/Videos && \
        chown -R "$user":"$user" /home/"$user"; \
    done

# Set all the passwords for the users
RUN chpasswd <<'EOF'
root:root
mark:mark
karma:karma
lily:lily
erik:erik
ned:ned
EOF

# Give mark sudo permissions
RUN echo "mark ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/mark

# Login as the user
USER mark

# Sets up the environment, fixes any layouts commonly used
ENV TERM=xterm-256color
ENV MSF_DATABASE_CONFIG=/dev/null

# Expose the internal simulation port for ssh
EXPOSE 2222

# Route all ssh logs to be sent to standard output, then keep the container alive with infinite loop
CMD /usr/sbin/sshd -D -p 2222 > /dev/stdout 2>&1 & tail -f /dev/null