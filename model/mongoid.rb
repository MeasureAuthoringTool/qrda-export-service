# Override the as_json method to ensure the _id is displayed as
# just the _id value as a string in the QRDA XML, "<_id>".
# Without this override it will be serialized as extended
# BSON::JSON, "{$oid => "<_id>"}"
module BSON
  class ObjectId
    def as_json(*args)
      to_s.as_json
    end
  end
end