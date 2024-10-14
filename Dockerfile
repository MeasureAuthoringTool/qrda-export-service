FROM phusion/passenger-ruby32:3.0.7
ENV HOME /root

CMD ["/sbin/my_init"]

# Enable nginx and Passenger
RUN rm -f /etc/service/nginx/down

# Remove the default site
RUN rm /etc/nginx/sites-enabled/default

# Create virtual host
ADD config/webapp.conf /etc/nginx/sites-enabled/webapp.conf

# Prepare folders
RUN mkdir /home/app/qrda-export

RUN bash -lc "apt update && apt upgrade -y && rvm get stable && rvm install ruby-3.2.5 && rvm --default use ruby-3.2.5"

# Add our app
COPY --chown=app:app . /home/app/qrda-export
RUN bundle config set --local deployment 'true'
RUN su - app -c "cd /home/app/qrda-export \
                && rvm-exec 3.2.5 bundle install"

# Clean up when done.
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && rm -rf /usr/local/rvm/rubies/ruby-3.2.5/lib/ruby/gems/3.2.0/gems/rvm-1.11.3.9