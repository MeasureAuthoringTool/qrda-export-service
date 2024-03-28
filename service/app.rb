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
    hosts: ['host.docker.internal:27017'],
    # hosts: ['localhost:27017'],
    database: 'admin',
  }
end

use Rack::JSONBodyParser

SCORING = {
  "Proportion" => "PROPORTION",
  "Ratio" => "RATIO",
  "Cohort" => "COHORT",
  "Continuous Variable" => "CONTINUOUS_VARIABLE"
}

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
# 9. Log formatting

put "/api/qrda" do
  content_type 'application/xml '

  #TODO probably don't need access token here, will remove after SME confirmation
  access_token = request.env["HTTP_Authorization"]
  measureDTO = request.params

  measure = CQM::Measure.new(JSON.parse(measureDTO["measure"]))
  test_cases = measureDTO["testCases"]

  qrdas = Array.new
  test_cases.each do | test_case |

    qdm_patient = QDM::Patient.new(JSON.parse(test_case["json"]))

    patient = CQM::Patient.new
    patient.qdmPatient = qdm_patient
    patient[:givenNames] = [test_case["title"]]
    patient[:familyName] = [test_case["series"]]

    expectedValues = Array.new
    test_case["groupPopulations"].each do | groupPopulation |
      groupPopulation["populationValues"].each do | populationValue |
        expectedValues.push(populationValue["expected"])
      end
    end
    patient[:expectedValues] = expectedValues
    #TODO look for more patient fields

    qrdas.push Qrda1R5.new(patient, measure, measureDTO["options"].symbolize_keys).render
  end
  qrdas
end

get "/api/health" do
  puts "QRDA Export Service is up"
  "QRDA Export Service is up"
end