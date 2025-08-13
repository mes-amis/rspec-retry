# RSpec::Retry ![CI](https://github.com/mes-amis/rspec-retry/actions/workflows/ci.yml/badge.svg?branch=main)

RSpec::Retry adds a `:retry` option for intermittently failing rspec examples.
If an example has the `:retry` option, rspec will retry the example the
specified number of times until the example succeeds.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'rspec-retry', group: :test # Unlike rspec, this doesn't need to be included in development group
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install rspec-retry

require in `spec_helper.rb`

```ruby
# spec/spec_helper.rb
require 'rspec/retry'

RSpec.configure do |config|
  # show retry status in spec process
  config.verbose_retry = true
  # show exception that triggers a retry if verbose_retry is set to true
  config.display_try_failure_messages = true

  # limit retries in CI to prevent long build times
  config.max_retries = ENV['CI'] ? 10 : false

  # skip retries for tests marked as flaky or known problematic tests
  config.skip_retry_if = proc do |example|
    example.metadata[:flaky] == true ||
    example.metadata[:problematic] == true
  end

  # run retry only on features
  config.around :each, :js do |ex|
    ex.run_with_retry retry: 3
  end

  # callback to be run between retries
  config.retry_callback = proc do |ex|
    # run some additional clean up task - can be filtered by example metadata
    if ex.metadata[:js]
      Capybara.reset!
    end
  end
end
```

## Usage

```ruby
it 'should randomly succeed', :retry => 3 do
  expect(rand(2)).to eq(1)
end

it 'should succeed after a while', :retry => 3, :retry_wait => 10 do
  expect(command('service myservice status')).to eq('started')
end
# run spec (following log is shown if verbose_retry options is true)
# RSpec::Retry: 2nd try ./spec/lib/random_spec.rb:49
# RSpec::Retry: 3rd try ./spec/lib/random_spec.rb:49
```

### Global Retry Limits

You can set a global limit on how many examples are allowed to retry during a test run:

```ruby
RSpec.configure do |config|
  # Only allow 5 examples to retry during the entire test run
  config.max_retries = 5
end

# Examples that would normally retry will fail immediately once the limit is reached
it 'first flaky test', :retry => 3 do
  # This will retry up to 3 times if it fails
end

it 'another flaky test', :retry => 2 do
  # This will retry if the global limit hasn't been reached
end
# ... after 5 examples have been retried, subsequent failing examples won't retry
```

### Conditional Retry Skipping

You can skip retries for specific examples based on custom conditions:

```ruby
RSpec.configure do |config|
  # Skip retries for integration tests
  config.skip_retry_if = proc do |example|
    example.description.match?(/integration/)
  end
end

it 'unit test', :retry => 3 do
  # This will retry on failure
end

it 'integration test', :retry => 3 do
  # This will NOT retry due to skip_retry_if condition
end
```

```ruby
RSpec.configure do |config|
  # Skip retries based on example metadata
  config.skip_retry_if = proc do |example|
    example.metadata[:no_retry] == true ||
    example.metadata[:type] == :integration
  end
end

it 'normal test', :retry => 2 do
  # Will retry on failure
end

it 'marked test', :retry => 2, :no_retry => true do
  # Will NOT retry due to metadata
end

it 'integration test', :retry => 2, :type => :integration do
  # Will NOT retry due to type metadata
end
```

**Flaky test tracking integration:**

```ruby
RSpec.configure do |config|
  config.max_retries = 10

  # Load known flaky specs from external tracking system
  FLAKY_SPECS ||= RSpec::Flakes.flaky_specs

  # Skip retries for tests that are known to be flaky
  # This prevents wasting time on tests that fail due to known issues
  config.skip_retry_if = proc do |example|
    metadata = example.metadata

    # Check if this test matches any known flaky spec
    FLAKY_SPECS.any? do |flaky_spec|
      metadata[:file_path].include?(flaky_spec['file']) &&
        example.full_description == flaky_spec['test_name']
    end
  end
end
```

### Calling `run_with_retry` programmatically

You can call `ex.run_with_retry(opts)` on an individual example.

## Configuration

- **:verbose_retry**(default: _false_) Print retry status
- **:display_try_failure_messages** (default: _false_) If verbose retry is enabled, print what reason forced the retry
- **:default_retry_count**(default: _1_) If retry count is not set in an example, this value is used by default. Note that currently this is a 'try' count. If increased from the default of 1, all examples will be retried. We plan to fix this as a breaking change in version 1.0.
- **:default_sleep_interval**(default: _0_) Seconds to wait between retries
- **:clear_lets_on_failure**(default: _true_) Clear memoized values for `let`s before retrying
- **:exceptions_to_hard_fail**(default: _[]_) List of exceptions that will trigger an immediate test failure without retry. Takes precedence over **:exceptions_to_retry**
- **:exceptions_to_retry**(default: _[]_) List of exceptions that will trigger a retry (when empty, all exceptions will)
- **:retry_callback**(default: _nil_) Callback function to be called between retries
- **:max_retries**(default: _false_) Global limit on the number of examples that can be retried. When disabled (false), there's no limit. When set to an integer, only that many examples will be allowed to retry during the entire test run
- **:skip_retry_if**(default: _nil_) Proc that takes an example as an argument. If it returns true, the example will not be retried even if it has a retry count configured

## Environment Variables

- **RSPEC_RETRY_RETRY_COUNT** can override the retry counts even if a retry count is set in an example or default_retry_count is set in a configuration.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a pull request
