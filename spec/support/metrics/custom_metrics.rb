class CustomMetrics < Influxer::Metrics
  tags :code, :user_id
  values :val
end
