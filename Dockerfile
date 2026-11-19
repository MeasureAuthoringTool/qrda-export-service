FROM phusion/passenger-ruby34:3.2.2
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

RUN bash -lc "rvm install ruby-3.4.13 && rvm --default use ruby-3.4.13" && \
    ln -sf /usr/local/rvm/gems/ruby-3.4.13/wrappers/ruby /usr/bin/ruby && \
    ln -sf /usr/local/rvm/gems/ruby-3.4.13/wrappers/ruby /usr/bin/ruby3.4 && \
    ln -sf /usr/local/rvm/gems/ruby-3.4.13/wrappers/bundle /usr/bin/bundle

# Add our app
COPY --chown=app:app . /home/app/qrda-export
RUN bundle config set --local deployment 'true'
RUN su - app -c "cd /home/app/qrda-export \
                && rvm-exec 3.4.13 bundle install"

# Clean up when done.
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
