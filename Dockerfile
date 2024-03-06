FROM phusion/passenger-ruby32:3.0.2
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

RUN bash -lc "rvm install ruby-3.2.3 && rvm --default use ruby-3.2.3"

# Add our app
COPY --chown=app:app . /home/app/qrda-export
RUN bundle config set --local deployment 'true'
RUN su - app -c "cd /home/app/qrda-export \
                && rvm-exec 3.2.3 bundle install"

# Clean up when done.
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*