# frozen_string_literal: true
require "bundler/setup"
require "sinatra"
require "cqm-reports"
require "cqm/models"
require 'rest-client'
require "rack"
require "rack/contrib"
require 'jwt'

puts "Loading QRDA Export Service"

# TODO move config to mongoid.yml file.
# Mongoid.load!("config/mongoid.yml")
Mongoid.configure do |config|
  config.clients.default = {
    uri: "#{ENV['MONGODB_URI']}"
  }
end

use Rack::JSONBodyParser

# Implementation pre-reqs
# 1. Parsing JSON input ✅
# 2. Porting over html generation from bonnie
# 3. JWT verification
# 4. Data requirements: what inputs do we need and where do we get that data from?
#     Looks like we'll only need the madie Measure object. It contains the array of test cases
#     and each testcase already contains an instance of QDM::Patient

# Service stand-up tasks
# 0. github repo ✅
# 1. Bundler setup ✅
# 2. Mongoid config ✅
# 3. Unit testing scaffolding
# 4. RDoc scaffolding
# 5. Containerization ✅
# 6. Clean up require statements
# 7. Clean up \class name
# 8. README, including how to run locally instructions

put "/api/qrda" do
  content_type 'text/xml'
  start_time = DateTime.parse(request.params["measure"]["measurementPeriodStart"])
  end_time = DateTime.parse(request.params["measure"]["measurementPeriodEnd"])
  options = { start_time: start_time, end_time: end_time }

  measure = request.params["measure"]
  test_cases = measure["testCases"]

  qrdas = Array.new
  test_cases.each do | test_case |

    qdm_patient = QDM::Patient.new(JSON.parse(test_case["json"]))

    patient = CQM::Patient.new
    patient.qdmPatient = qdm_patient
    patient[:givenNames] = [test_case["title"]]

    qrdas.push Qrda1R5.new(patient, [measure], options).render
  end
  qrdas
end

get "/api/health" do
  puts "QRDA Export Service is up"
  "QRDA Export Service is up"
end
