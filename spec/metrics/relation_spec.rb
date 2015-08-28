require 'spec_helper'

describe Influxer::Relation, :query do
  let(:rel) { Influxer::Relation.new DummyMetrics }
  let(:rel2) { Influxer::Relation.new DummyComplexMetrics }

  context "instance methods" do
    subject { rel }

    specify { is_expected.to respond_to :write }
    specify { is_expected.to respond_to :select }
    specify { is_expected.to respond_to :where }
    specify { is_expected.to respond_to :limit }
    specify { is_expected.to respond_to :group }
    specify { is_expected.to respond_to :delete_all }
    specify { is_expected.to respond_to :to_sql }
  end

  describe "#build" do
    specify { expect(rel.build).to be_a DummyMetrics }
    specify { expect(rel.new).to be_a DummyMetrics }
  end

  describe "#merge!" do
    it "merge multi values" do
      r1 = rel.where(id: [1, 2], dummy: 'qwe').time(:hour)
      r2 = Influxer::Relation.new(DummyMetrics).where.not(user_id: 0).group(:user_id)
      r1.merge!(r2)
      expect(r1.to_sql).to eq "select * from \"dummy\" group by time(1h),user_id where (id=1 or id=2) and (dummy='qwe') and (user_id<>0)"
    end

    it "merge single values" do
      r1 = rel.time(:hour, fill: 0).limit(10)
      r2 = Influxer::Relation.new(DummyMetrics).merge(:doomy).limit(5)
      r1.merge!(r2)
      expect(r1.to_sql).to eq "select * from \"dummy\" merge \"doomy\" group by time(1h) fill(0) limit 5"
    end
  end

  describe "sql generation" do
    describe "#from" do
      it "generates valid from if no conditions" do
        expect(rel.to_sql).to eq "select * from \"dummy\""
      end
    end

    describe "#select" do
      it "select array of symbols" do
        expect(rel.select(:user_id, :dummy_id).to_sql).to eq "select user_id,dummy_id from \"dummy\""
      end

      it "select string" do
        expect(rel.select("count(user_id)").to_sql).to eq "select count(user_id) from \"dummy\""
      end
    end

    describe "#where" do
      it "sgenerate valid conditions from hash" do
        Timecop.freeze(Time.now)
        expect(rel.where(user_id: 1, dummy: 'q', timer: Time.now).to_sql).to eq "select * from \"dummy\" where (user_id=1) and (dummy='q') and (timer=#{Time.now.to_i}s)"
      end

      it "generate valid conditions from strings" do
        expect(rel.where("time > now() - 1d").to_sql).to eq "select * from \"dummy\" where (time > now() - 1d)"
      end

      it "handle regexps" do
        expect(rel.where(user_id: 1, dummy: /^du.*/).to_sql).to eq "select * from \"dummy\" where (user_id=1) and (dummy=~/^du.*/)"
      end

      it "handle ranges" do
        expect(rel.where(user_id: 1..4).to_sql).to eq "select * from \"dummy\" where (user_id>1 and user_id<4)"
      end

      it "handle arrays" do
        expect(rel.where(user_id: [1, 2, 3]).to_sql).to eq "select * from \"dummy\" where (user_id=1 or user_id=2 or user_id=3)"
      end
    end

    describe "#not" do
      it "negate simple values" do
        expect(rel.where.not(user_id: 1, dummy: :a).to_sql).to eq "select * from \"dummy\" where (user_id<>1) and (dummy<>'a')"
      end

      it "handle regexp" do
        expect(rel.where.not(user_id: 1, dummy: /^du.*/).to_sql).to eq "select * from \"dummy\" where (user_id<>1) and (dummy!~/^du.*/)"
      end

      it "handle ranges" do
        expect(rel.where.not(user_id: 1..4).to_sql).to eq "select * from \"dummy\" where (user_id<1 and user_id>4)"
      end

      it "handle arrays" do
        expect(rel.where.not(user_id: [1, 2, 3]).to_sql).to eq "select * from \"dummy\" where (user_id<>1 and user_id<>2 and user_id<>3)"
      end
    end

    describe "#merge" do
      it "merge with one series" do
        expect(rel.merge("dubby").to_sql).to eq "select * from \"dummy\" merge \"dubby\""
      end

      it "merge with one series as regexp" do
        expect(rel.merge(/^du[1-6]+$/).to_sql).to eq "select * from \"dummy\" merge /^du[1-6]+$/"
      end
    end

    describe "#past" do
      it "work with predefined symbols" do
        expect(rel.past(:hour).to_sql).to eq "select * from \"dummy\" where (time > now() - 1h)"
      end

      it "work with any symbols" do
        expect(rel.past(:s).to_sql).to eq "select * from \"dummy\" where (time > now() - 1s)"
      end

      it "work with strings" do
        expect(rel.past("3d").to_sql).to eq "select * from \"dummy\" where (time > now() - 3d)"
      end

      it "work with numbers" do
        expect(rel.past(1.day).to_sql).to eq "select * from \"dummy\" where (time > now() - 86400s)"
      end
    end

    describe "#since" do
      it "work with datetime" do
        expect(rel.since(Time.utc(2014, 12, 31)).to_sql).to eq "select * from \"dummy\" where (time > 1419984000s)"
      end
    end

    describe "#group" do
      it "generate valid groups" do
        expect(rel.group(:user_id, "time(1m) fill(0)").to_sql).to eq "select * from \"dummy\" group by user_id,time(1m) fill(0)"
      end

      context "group by time predefined values" do
        it "group by hour" do
          expect(rel.time(:hour).to_sql).to eq "select * from \"dummy\" group by time(1h)"
        end

        it "group by minute" do
          expect(rel.time(:minute).to_sql).to eq "select * from \"dummy\" group by time(1m)"
        end

        it "group by second" do
          expect(rel.time(:second).to_sql).to eq "select * from \"dummy\" group by time(1s)"
        end

        it "group by millisecond" do
          expect(rel.time(:ms).to_sql).to eq "select * from \"dummy\" group by time(1u)"
        end

        it "group by day" do
          expect(rel.time(:day).to_sql).to eq "select * from \"dummy\" group by time(1d)"
        end

        it "group by week" do
          expect(rel.time(:week).to_sql).to eq "select * from \"dummy\" group by time(1w)"
        end

        it "group by month" do
          expect(rel.time(:month).to_sql).to eq "select * from \"dummy\" group by time(30d)"
        end

        it "group by hour and fill" do
          expect(rel.time(:month, fill: 0).to_sql).to eq "select * from \"dummy\" group by time(30d) fill(0)"
        end
      end

      it "group by time with string value" do
        expect(rel.time("4d").to_sql).to eq "select * from \"dummy\" group by time(4d)"
      end

      it "group by time with string value and fill null" do
        expect(rel.time("4d", fill: :null).to_sql).to eq "select * from \"dummy\" group by time(4d) fill(null)"
      end

      it "group by time and other fields with fill null" do
        expect(rel.time("4d", fill: 0).group(:dummy_id).to_sql).to eq "select * from \"dummy\" group by time(4d),dummy_id fill(0)"
      end
    end

    describe "#limit" do
      it "generate valid limit" do
        expect(rel.limit(100).to_sql).to eq "select * from \"dummy\" limit 100"
      end
    end

    describe "calculations" do
      context "one arg calculation methods" do
        [
          :count, :min, :max, :mean,
          :mode, :median, :distinct, :derivative,
          :stddev, :sum, :first, :last, :difference, :histogram
        ].each do |method|
          describe "##{method}" do
            specify do
              expect(rel.where(user_id: 1).calc(method, :column_name).to_sql)
                .to eq "select #{method}(column_name) from \"dummy\" where (user_id=1)"
            end
          end
        end
      end

      context "two args calculation methods" do
        [
          :percentile, :histogram, :top, :bottom
        ].each do |method|
          describe "##{method}" do
            specify do
              expect(rel.where(user_id: 1).calc(method, :column_name, 10).to_sql)
                .to eq "select #{method}(column_name,10) from \"dummy\" where (user_id=1)"
            end
          end
        end
      end
    end
  end

  describe "#empty?" do
    it "return false if has points" do
      allow(client).to receive(:query) { { points: [{ time: 1, id: 2 }] } }
      expect(rel.empty?).to be_falsey
      expect(rel.present?).to be_truthy
    end

    it "return true if no points" do
      allow(client).to receive(:query) { { points: [] } }
      expect(rel.empty?).to be_truthy
      expect(rel.present?).to be_falsey
    end
  end

  describe "#delete_all" do
    it do
      Timecop.freeze(Time.now) do
        expect(rel.where(user_id: 1, dummy: 'q', timer: Time.now).delete_all)
          .to eq "delete from \"dummy\" where (user_id=1) and (dummy='q') and (timer=#{Time.now.to_i}s)"
      end
    end
  end

  describe "#inspect" do
    it "return correct String represantation of empty relation" do
      allow(client).to receive(:query) { { points: [] } }
      expect(rel.inspect).to eq "#<Influxer::Relation []>"
    end

    it "return correct String represantation of non-empty relation" do
      allow(client).to receive(:query) { { "dummy" => [1, 2, 3] } }
      expect(rel.inspect).to eq "#<Influxer::Relation [1, 2, 3]>"
    end

    it "return correct String represantation of non-empty large (>11) relation" do
      allow(client).to receive(:query) { { "dummy" => [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13] } }
      expect(rel.inspect).to eq "#<Influxer::Relation [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, ...]>"
    end
  end
end
