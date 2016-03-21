class UserMetrics < Influxer::Metrics
  tags :user_id
  values :time_spent
end
