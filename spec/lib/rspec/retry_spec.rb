require 'spec_helper'

describe RSpec::Retry do
  def count
    @count ||= 0
    @count
  end

  def count_up
    @count ||= 0
    @count += 1
  end

  def set_expectations(expectations)
    @expectations = expectations
  end

  def shift_expectation
    @expectations.shift
  end

  class RetryError < StandardError; end
  class RetryChildError < RetryError; end
  class HardFailError < StandardError; end
  class HardFailChildError < HardFailError; end
  class OtherError < StandardError; end
  class SharedError < StandardError; end
  before(:all) do
    ENV.delete('RSPEC_RETRY_RETRY_COUNT')
  end

  context 'no retry option' do
    it 'should work' do
      expect(true).to be(true)
    end
  end

  context 'with retry option' do
    before(:each) { count_up }

    context do
      before(:all) { set_expectations([false, false, true]) }

      it 'should run example until :retry times', :retry => 3 do
        expect(true).to be(shift_expectation)
        expect(count).to eq(3)
      end
    end

    context do
      before(:all) { set_expectations([false, true, false]) }

      it 'should stop retrying if  example is succeeded', :retry => 3 do
        expect(true).to be(shift_expectation)
        expect(count).to eq(2)
      end
    end

    context 'with lambda condition' do
      before(:all) { set_expectations([false, true]) }

      it "should get retry count from condition call", retry_me_once: true do
        expect(true).to be(shift_expectation)
        expect(count).to eq(2)
      end
    end

    context 'with :retry => 0' do
      shared_state = { ran_once: false }
      
      it 'should still run once', retry: 0 do
        shared_state[:ran_once] = true
      end

      it 'should run have run once' do
        expect(shared_state[:ran_once]).to be true
      end
    end

    context 'with the environment variable RSPEC_RETRY_RETRY_COUNT' do
      before(:all) do
        set_expectations([false, false, true])
        ENV['RSPEC_RETRY_RETRY_COUNT'] = '3'
      end

      after(:all) do
        ENV.delete('RSPEC_RETRY_RETRY_COUNT')
      end

      it 'should override the retry count set in an example', :retry => 2 do
        expect(true).to be(shift_expectation)
        expect(count).to eq(3)
      end
    end

    context "with exponential backoff enabled", :retry => 3, :retry_wait => 0.001, :exponential_backoff => true do
      context do
        before(:all) do
          set_expectations([false, false, true])
          @start_time = Time.now
        end

        it 'should run example until :retry times', :retry => 3 do
          expect(true).to be(shift_expectation)
          expect(count).to eq(3)
          expect(Time.now - @start_time).to be >= (0.001)
        end
      end
    end

    describe "with a list of exceptions to immediately fail on", :retry => 2, :exceptions_to_hard_fail => [HardFailError] do
      context "the example throws an exception contained in the hard fail list" do
        it "does not retry" do
          expect(count).to be < 2
          pending "This should fail with a count of 1: Count was #{count}"
          raise HardFailError unless count > 1
        end
      end

      context "the example throws a child of an exception contained in the hard fail list" do
        it "does not retry" do
          expect(count).to be < 2
          pending "This should fail with a count of 1: Count was #{count}"
          raise HardFailChildError unless count > 1
        end
      end

      context "the throws an exception not contained in the hard fail list" do
        it "retries the maximum number of times" do
          raise OtherError unless count > 1
          expect(count).to eq(2)
        end
      end
    end

    describe "with a list of exceptions to retry on", :retry => 2, :exceptions_to_retry => [RetryError] do
      context do
        let(:rspec_version) { RSpec::Core::Version::STRING }

        let(:example_code) do
          %{
            $count ||= 0
            $count += 1

            raise NameError unless $count > 2
          }
        end

        let!(:example_group) do
          $count, $example_code = 0, example_code

          RSpec.describe("example group", exceptions_to_retry: [NameError], retry: 3).tap do |this|
            this.run # initialize for rspec 3.3+ with no examples
          end
        end

        let(:retry_attempts) do
          example_group.examples.first.metadata[:retry_attempts]
        end

        it 'should retry and match attempts metadata' do
          example_group.example { instance_eval($example_code) }
          example_group.run

          expect(retry_attempts).to eq(2)
        end

        let(:retry_exceptions) do
          example_group.examples.first.metadata[:retry_exceptions]
        end

        it 'should add exceptions into retry_exceptions metadata array' do
          example_group.example { instance_eval($example_code) }
          example_group.run

          expect(retry_exceptions.count).to eq(2)
          expect(retry_exceptions[0].class).to eq NameError
          expect(retry_exceptions[1].class).to eq NameError
        end
      end

      context "the example throws an exception contained in the retry list" do
        it "retries the maximum number of times" do
          raise RetryError unless count > 1
          expect(count).to eq(2)
        end
      end

      context "the example throws a child of an exception contained in the retry list" do
        it "retries the maximum number of times" do
          raise RetryChildError unless count > 1
          expect(count).to eq(2)
        end
      end

      context "the example fails (with an exception not in the retry list)" do
        it "only runs once" do
          set_expectations([false])
          expect(count).to eq(1)
        end
      end

      context 'the example retries exceptions which match with case equality' do
        class CaseEqualityError < StandardError
          def self.===(other)
            # An example of dynamic matching
            other.message == 'Rescue me!'
          end
        end

        it 'retries the maximum number of times', exceptions_to_retry: [CaseEqualityError] do
          raise StandardError, 'Rescue me!' unless count > 1
          expect(count).to eq(2)
        end
      end
    end

    describe "with both hard fail and retry list of exceptions", :retry => 2, :exceptions_to_retry => [SharedError, RetryError], :exceptions_to_hard_fail => [SharedError, HardFailError] do
      context "the exception thrown exists in both lists" do
        it "does not retry because the hard fail list takes precedence" do
          expect(count).to be < 2
          pending "This should fail with a count of 1: Count was #{count}"
          raise SharedError unless count > 1
        end
      end

      context "the example throws an exception contained in the hard fail list" do
        it "does not retry because the hard fail list takes precedence" do
          expect(count).to be < 2
          pending "This should fail with a count of 1: Count was #{count}"
          raise HardFailError unless count > 1
        end
      end

      context "the example throws an exception contained in the retry list" do
        it "retries the maximum number of times because the hard fail list doesn't affect this exception" do
          raise RetryError unless count > 1
          expect(count).to eq(2)
        end
      end

      context "the example throws an exception contained in neither list" do
        it "does not retry because the the exception is not in the retry list" do
          expect(count).to be < 2
          pending "This should fail with a count of 1: Count was #{count}"
          raise OtherError unless count > 1
        end
      end
    end
  end

  describe 'clearing lets' do
    before(:all) do
      @control = true
    end

    let(:let_based_on_control) { @control }

    after do
      @control = false
    end

    it 'should clear the let when the test fails so it can be reset', :retry => 2 do
      expect(let_based_on_control).to be(false)
    end

    it 'should not clear the let when the test fails', :retry => 2, :clear_lets_on_failure => false do
      expect(let_based_on_control).to be(!@control)
    end
  end

  describe 'running example.run_with_retry in an around filter', retry: 2 do
    before(:each) { count_up }
    before(:all) do
      set_expectations([false, false, true])
    end

    it 'allows retry options to be overridden', :overridden do
      expect(RSpec.current_example.metadata[:retry]).to eq(3)
    end

    it 'uses the overridden options', :overridden do
      expect(true).to be(shift_expectation)
      expect(count).to eq(3)
    end
  end

  describe 'calling retry_callback between retries', retry: 2 do
    before(:all) do
      RSpec.configuration.retry_callback = proc do |example|
        @retry_callback_called = true
        @example = example
      end
    end

    after(:all) do
      RSpec.configuration.retry_callback = nil
    end

    context 'if failure' do
      before(:all) do
        @retry_callback_called = false
        @example = nil
        @retry_attempts = 0
      end

      it 'should call retry callback', with_some: 'metadata' do |example|
        if @retry_attempts == 0
          @retry_attempts += 1
          expect(@retry_callback_called).to be(false)
          expect(@example).to eq(nil)
          raise "let's retry once!"
        elsif @retry_attempts > 0
          expect(@retry_callback_called).to be(true)
          expect(@example).to eq(example)
          expect(@example.metadata[:with_some]).to eq('metadata')
        end
      end
    end

    context 'does not call retry_callback if no errors' do
      before(:all) do
        @retry_callback_called = false
        @example = nil
      end

      after do
        expect(@retry_callback_called).to be(false)
        expect(@example).to be_nil
      end

      it { true }
    end
  end

  describe 'Example::Procsy#attempts' do
    it 'should be exposed' do
      results = {}
      
      example_group = RSpec.describe do
        around do |example|
          example.run_with_retry
          results[example.description] = [example.exception.nil?, example.attempts]
        end

        specify 'without retry option' do
          expect(true).to be(true)
        end

        specify 'with retry option', retry: 3 do
          expect(true).to be(false)
        end
      end
      
      example_group.run
      expect(results).to eq({
        'without retry option' => [true, 1],
        'with retry option' => [false, 3]
      })
    end
  end

  describe 'output in verbose mode' do

    line_1 = __LINE__ + 8
    line_2 = __LINE__ + 11
    let(:group) do
      RSpec.describe 'ExampleGroup', retry: 2 do
        after do
          fail 'broken after hook'
        end

        it 'passes' do
          true
        end

        it 'fails' do
          fail 'broken spec'
        end
      end
    end

    it 'outputs failures correctly' do
      RSpec.configuration.output_stream = output = StringIO.new
      RSpec.configuration.verbose_retry = true
      RSpec.configuration.display_try_failure_messages = true
      expect {
        group.run RSpec.configuration.reporter
      }.to change { output.string }.to a_string_including <<-STRING.gsub(/^\s+\| ?/, '')
        | 1st Try error in ./spec/lib/rspec/retry_spec.rb:#{line_1}:
        | broken after hook
        |
        | RSpec::Retry: 2nd try ./spec/lib/rspec/retry_spec.rb:#{line_1}
        | F
        | 1st Try error in ./spec/lib/rspec/retry_spec.rb:#{line_2}:
        | broken spec
        | broken after hook
        |
        | RSpec::Retry: 2nd try ./spec/lib/rspec/retry_spec.rb:#{line_2}
      STRING
    end
  end

  describe 'max_retries configuration' do
    before(:all) do
      RSpec::Retry.reset_retried_examples_count
      RSpec.configuration.max_retries = 1  # Allow only 1 example to be retried
    end

    after(:all) do
      RSpec.configuration.max_retries = false  # reset to default
    end

    context 'when max_retries limit is reached' do
      it 'should stop retrying examples after max_retries limit is reached' do
        RSpec::Retry.reset_retried_examples_count
        RSpec.configuration.max_retries = 1  # Force set the limit
        attempt_counts = []
        
        example_group = RSpec.describe 'MaxRetriesTest' do
          around do |example|
            example.run_with_retry
            attempt_counts << example.attempts
          end

          it 'first failing example', retry: 3 do
            raise 'first failure'
          end

          it 'second failing example', retry: 3 do
            raise 'second failure'
          end

          it 'third failing example', retry: 3 do
            raise 'third failure'  # This should not retry due to max_retries limit
          end
        end
        
        example_group.run
        
        # With max_retries = 1, only first example should be retried to its full count
        # Second and third examples should not be retried at all (attempts = 1)
        expect(attempt_counts).to eq([3, 1, 1])  # First retries fully, second and third fail immediately
      end
    end

    context 'when under max_retries limit' do
      it 'should retry both examples when under max_retries limit' do
        RSpec::Retry.reset_retried_examples_count
        attempt_counts = []

        example_group = RSpec.describe 'UnderLimitTest' do
          around do |example|
            example.run_with_retry
            attempt_counts << example.attempts
          end

          it 'first failing example', retry: 2 do
            raise 'failure'
          end

          it 'second failing example', retry: 2 do
            raise 'failure'
          end
        end
        
        example_group.run
        expect(attempt_counts).to eq([2, 2])  # Both examples should retry fully
      end
    end

    context 'default max_retries value' do
      it 'should have a default value of false' do
        # Reset to default
        RSpec.configure { |config| config.max_retries = false }
        expect(RSpec.configuration.max_retries).to eq(false)
      end
    end

    context 'when max_retries is false' do
      it 'should ignore the max_retries feature completely' do
        RSpec::Retry.reset_retried_examples_count
        RSpec.configuration.max_retries = false
        attempt_counts = []

        example_group = RSpec.describe 'IgnoredMaxRetriesTest' do
          around do |example|
            example.run_with_retry
            attempt_counts << example.attempts
          end

          # Create many examples that will retry
          (1..15).each do |i|
            it "example #{i}", retry: 2 do
              raise "failure #{i}"
            end
          end
        end
        
        example_group.run
        
        # All 15 examples should retry fully since max_retries is disabled
        expect(attempt_counts).to eq([2] * 15)
      end
    end
  end
end
