class VisitsMetrics < Influxer::Metrics
  tags :user_id, :gender
  values :age, :page
end
