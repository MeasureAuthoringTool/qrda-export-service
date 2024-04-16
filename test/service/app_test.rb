ENV['APP_ENV'] = 'test'
# $LOAD_PATH.unshift File.expand_path('../../service', __FILE__)

require_relative '../../service/app'
require 'minitest/autorun'
require 'rack/test'

class AppTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def test_has_a_health_check
    get '/api/health'
    assert last_response.ok?
    assert_equal 'QRDA Export Service is up', last_response.body
  end

  def test_qrda_with_empty_payload
    put 'api/qrda'

  end

  def test_build_source_data_criteria
    criteria = {
      "oid" => "2.16.840.1.113762.1.4.1151.59",
      "title" => "Hospital Services for Urology",
      "description" => "Encounter, Performed: Hospital Services for Urology",
      "type" => "EncounterPerformed",
      "drc" => false,
      "codeId" => nil,
      "name" => "Hospital Services for Urology"
    }
    source_criteria = build_source_data_criteria(criteria)
    assert source_criteria.is_a?(QDM::EncounterPerformed)
    assert_equal criteria["oid"], source_criteria.codeListId
    assert_equal criteria["description"], source_criteria.description
  end

end