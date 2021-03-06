# frozen_string_literal: true

require "spec_helper"
require "support"

RSpec.describe "a load test" do
  def with_workers(num_workers)
    stop_threads = Array.new(num_workers).map do
      stop = false
      Thread.new do
        AdapterSupport.with_connection do |conn|
          worker = What::Worker.new(conn)
          until stop
            worker.work("default")
            sleep 0.01
          end
        end
      end
      -> { stop = true }
    end
    yield
  ensure
    stop_threads.each(&:call)
  end

  context "when many jobs are being worked concurrently" do
    let(:job_count) { 100 }
    let(:worker_count) { 15 }

    it "successfully works them all" do
      job_count.times { |i| CreatePayment.enqueue(i) }

      with_workers(worker_count) do
        sleep 0.1 while WhatJob.count > 0

        expect(Payment.count).to eq(job_count)
        expect(Payment.all.map(&:amount).uniq.count).to eq(job_count)
      end
    end
  end

  context "when many jobs are being worked and some fail" do
    let(:successful_job_count) { 100 }
    let(:failed_job_count) { 50 }
    let(:worker_count) { 3 }

    it "works every job once" do
      successful_job_count.times { |i| CreatePayment.enqueue(i) }
      failed_job_count.times { |i| BlowUp.enqueue(i) }

      expect(WhatJob.count).to eq(successful_job_count + failed_job_count)

      with_workers(worker_count) do
        sleep 0.1 while WhatJob.count > failed_job_count

        expect(Payment.count).to eq(successful_job_count)
        expect(Payment.all.map(&:amount).uniq.count).to eq(successful_job_count)

        expect(WhatJob.count).to eq(failed_job_count)

        # This is needed so the following expectation passes
        # TODO: why?
        sleep 0.5
        expect(WhatJob.all.map(&:error_count).uniq).to eq([1])

        expect(WhatJob.all.map(&:last_error).uniq.count).to eq(failed_job_count)
      end
    end
  end
end
