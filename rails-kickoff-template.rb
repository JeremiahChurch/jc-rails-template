# frozen_string_literal: true

RAILS_REQUIREMENT = '>= 6.0.2'
RUBY_REQUIREMENT = '>= 2.6.3'
REPOSITORY_PATH = 'https://raw.githubusercontent.com/JeremiahChurch/jc-rails-template/master'
$using_sidekiq = false

YES_ALL = ENV['YES_ALL'] == '1'

def yes?(*a)
  return true if YES_ALL

  super
end

def no?(*a)
  return false if YES_ALL

  super
end

def git_proxy(**args)
  git args if $use_git
end

def git_proxy_commit(msg)
  git_proxy add: '.'
  git_proxy commit: %( -m "#{msg}" --no-verify )
end

def run_template!
  assert_minimum_rails_and_ruby_version!
  $use_git = yes?('Do you want to add git commits (recommended)')

  git_proxy_commit 'Initial commit'

  after_bundle do
    git_proxy_commit 'Commit after bundle'
    run 'bin/spring stop'
  end

  setup_sidekiq

  add_gems
  main_config_files
  heroku_ci_file
  enable_uuid_extensions

  setup_testing
  setup_slim
  enable_discard
  setup_oj
  setup_newrelic
  setup_environments

  # setup_javascript
  setup_generators
  setup_readme
  # fix_bundler_binstub # seemingly no longer needed?
  setup_simple_form
  setup_pghero_annotate_and_blazer

  # jest?
  # see what is needed for pagy setup

  setup_commit_hooks
  setup_linters
  create_database

  generate_tmp_dirs

  output_final_instructions
end

def add_gems
  comment_lines 'Gemfile', 'jbuilder'

  gem 'slim-rails'
  gem 'simple_form'
  # gem 'pagy' # fast pagination - included in applicationcontroller
  gem 'jb' # jbuilder alternative https://github.com/amatsuda/jb
  gem 'discard', '~> 1.0' # the newer faster version of paranoia - soft delete
  gem 'oj' # fast json - see oj.rb in initializers
  gem 'goldiloader'
  gem 'enum_help' # only needed if you're using rails views & enums

  # monitoring
  gem 'blazer' # https://github.com/ankane/blazer
  gem 'pghero' # https://github.com/ankane/pghero/blob/master/guides/Rails.md

  gem 'sendgrid-actionmailer' # email

  gem_group :production do
    gem 'rack-timeout'
  end

  gem_group :development, :test do
    gem 'rspec-rails'
    gem 'factory_bot_rails'
    gem 'dotenv-rails'
  end

  gem_group :development do
    gem 'bullet'
    gem 'brakeman' # static security scanner
    gem 'bundler-audit' # security issues
    gem 'bundler-leak' # memory issues
    gem 'annotate'
  end

  gem_group :test do
    gem 'capybara'
    gem 'capybara-selenium'
    gem 'shoulda-matchers'
  end

  git_proxy_commit 'Add custom gems'
end

def setup_slim
  after_bundle do
    run 'gem install html2slim --no-document'
    run 'erb2slim app/views/ -d'
    run 'gem uninstall html2slim -x'
    git_proxy_commit 'Use Slim'
  end
end

def enable_uuid_extensions
  bundle_command 'exec rails generate migration enable_uuid_extensions'
  migration = Dir.glob('db/migrate/*enable_uuid_extensions.rb').first # #glob returns array
  inject_into_file migration, after: /def change\n/ do
    <<-RB
    enable_extension "uuid-ossp"
    enable_extension "pgcrypto"
    RB
  end

  inject_into_class 'app/models/application_record.rb', 'ApplicationRecord' do
    <<-RB
      self.implicit_order_column = 'created_at' # used in place of uuid column since it isn't numeric
    RB
  end
end

def setup_pghero_annotate_and_blazer
  bundle_command 'exec rails generate pghero:query_stats'
  bundle_command 'exec rails generate pghero:space_stats'

  bundle_command 'exec rails g annotate:install'

  bundle_command 'exec rails generate blazer:install'
  insert_into_file 'config/routes.rb',
                   "    mount PgHero::Engine, at: \"pghero\"\n    mount Blazer::Engine, at: \"blazer\"\n\n",
                   after: "Rails.application.routes.draw do\n"
end

def setup_simple_form
  after_bundle do
    if yes?('Configure Simpleform to use bootstrap?')
      bundle_command 'exec rails generate simple_form:install --bootstrap'
      run 'yarn add bootstrap --save'
      create_file 'app/javascript/stylesheets/application.scss' do
        <<-RB
  // ~ to tell webpack that this is not a relative import:
  @import '~bootstrap/dist/css/bootstrap';
        RB
      end

      inject_into_file 'app/javascript/packs/application.js', before: /\z/ do
        <<-RB
    import '../stylesheets/application.scss'
        RB
      end

      gsub_file 'app/views/layouts/application.html.slim', /stylesheet_link_tag/, 'stylesheet_pack_tag'

    else
      bundle_command 'exec rails generate simple_form:install'
    end
    run 'yarn add resolve-url-loader --save'
    inject_into_file 'app/config/webpack/environment.js', before: /module.exports/ do <<~ENVIRONMENT
        // resolve-url-loader must be used before sass-loader
        environment.loaders.get('sass').use.splice(-1, 0, {
          loader: 'resolve-url-loader',
        });
      ENVIRONMENT
    end



    git_proxy_commit 'Initialized simpleform'
  end
end

def setup_environments
  inject_into_file 'config/environments/development.rb', before: /^end\n/ do
    <<-RB
  config.after_initialize do
    # https://github.com/flyerhzm/bullet#configuration
    Bullet.enable = true
    Bullet.rails_logger = true
  end
    RB
  end
  git_proxy_commit 'Configure Bullet in development & console permissions'

  inject_into_file 'config/environments/development.rb', before: /^end\n/ do
    <<-RB
  if ENV['SEND_EMAIL'] && ENV['SEND_EMAIL'] == 'true'
    config.action_mailer.delivery_method = :sendgrid_actionmailer
    config.action_mailer.sendgrid_actionmailer_settings = {
      api_key: ENV['SENDGRID_API_KEY'],
      raise_delivery_errors: true
    }
    config.action_mailer.perform_deliveries = true
  else
    config.action_mailer.perform_deliveries = false
  end
    RB
  end
  git_proxy_commit 'Sendgrid email setup'

  inject_into_file 'config/environments/development.rb', before: /^end\n/ do
    <<-RB
  # whitelist testing domain
  config.hosts << 'app.test'

  config.web_console.permissions = '0.0.0.0/0'
    RB
  end
  git_proxy_commit 'Whitelist console permissions'

  gsub_file(
    'config/environments/production.rb',
    /config\.log_level = :debug/,
    'config.log_level = ENV.fetch("LOG_LEVEL", "info").to_sym'
  )
  git_proxy_commit 'Make :info the default log_level in production'

  %w[development test].each do |env|
    inject_into_file "config/environments/#{env}.rb", before: /^end\n/ do
      "\n  config.action_controller.action_on_unpermitted_parameters = :raise\n"
    end
  end
  git_proxy_commit 'Raise an error when unpermitted parameters in development'
end

def output_final_instructions
  after_bundle do
    msg = <<~MSG
      Template Completed!

      Please review the above output for issues.

      To finish setup, you must prepare Heroku with at minimum the following steps
      1) Configure Newrelic
      2) Setup Redis (if using Sidekiq)
      3) Setup Sendgrid add-in in Heroku
      4) Setup lib/tasks/scheduler.rake in Heroku Scheduler to run nightly!
      5) Review your README.md file for needed updates
      6) Review your Gemfile for formatting
      7) If you ran the install command with webpack=react, you also need to run: `rails webpacker:install:react`
    MSG

    say msg, :cyan
  end
end

# def setup_javascript
#  uncomment_lines "bin/setup", "bin/yarn"
#
#  git_proxy_commit "Configure Javascript"
# end

def setup_sidekiq
  $using_sidekiq = yes?('Do you want to setup Sidekiq?')

  return unless $using_sidekiq

  gem 'sidekiq'

  after_bundle do
    insert_into_file 'config/application.rb',
                     "    config.active_job.queue_adapter = :sidekiq\n\n",
                     after: "class Application < Rails::Application\n"

    append_file 'Procfile', <<~PROCFILE
      worker: RAILS_MAX_THREADS=${SIDEKIQ_CONCURRENCY:-25} bundle exec sidekiq -t 25 -q default -q mailers
    PROCFILE

    insert_into_file 'config/routes.rb',
                     "    require \"sidekiq/web\"\n    mount Sidekiq::Web => \"/sidekiq\"\n\n",
                     after: "Rails.application.routes.draw do\n"

    git_proxy_commit 'Setup Sidekiq'
  end
end

def setup_linters
  after_bundle do
    create_file '.eslintrc.yml', <<~ESLINTRC
      env:
        browser: true
        es6: true
      extends:
        [# skip screen reader usability for now https://github.com/airbnb/javascript/issues/1665#issuecomment-466318869
        airbnb-base,
        airbnb/rules/react,
        "plugin:@typescript-eslint/recommended",
        plugin:import/typescript
        ]
      parser: "@typescript-eslint/parser"
      globals:
        Atomics: readonly
        SharedArrayBuffer: readonly
      parserOptions:
        ecmaFeatures:
          jsx: true
        ecmaVersion: 2018
        sourceType: module
      plugins:
        - react
        - react-hooks
        - "@typescript-eslint"
      settings:
        "import/resolver": webpack
      rules: {
               max-len: [ 2, { code: 120, ignoreUrls: true} ], # increase line length from 100 to 120
               # FIXME: turn these back on when we get some semblance of code stability
               react/prop-types: off,
               react/destructuring-assignment: off,
               react/prefer-stateless-function: off,
               no-unused-expressions: ['error', allowTernary: true ],
               import/no-cycle: off,
               no-shadow: off, # refactoring to get rid of these is a good one - these are ugly to read
               react-hooks/exhaustive-deps: off, # I write shitty code and don't fully understand these yet
               '@typescript-eslint/explicit-function-return-type': off, # for now... until I get bored and want to go add them in
               '@typescript-eslint/no-explicit-any': off # same as above...
      }
      overrides:
        [
        { # /test/react - all of our testing - sets up jest and etc rules - enforces .test.js extension ONLY - NO JSX ext
          files: [
            "*.test.{js,ts,tsx}"
          ],
          env: {
            jest: true #// now **/*.test.js files' env has both es6 *and* jest
          },
            extends: [plugin:jest/recommended],
            plugins: [jest],
          rules: {
            "jest/no-disabled-tests": "warn",
            "jest/no-focused-tests": "error",
            "jest/no-identical-title": "error",
            "jest/prefer-to-have-length": "warn",
            "jest/valid-expect": "error",
            "react/jsx-filename-extension": [1, { "extensions": [".js"] }], # follow the jest pattern and use js
          }
        },
        { # all of our storybook .stories.js files
          files: [
            "*.stories.js"
          ],
          rules: {
            "react/jsx-filename-extension": [1, { "extensions": [".js"] }], # follow the jest pattern and use js
          }
        },
        { # all of our typescript files
          files: [
            "*.tsx"
          ],
          rules: {
            "react/jsx-filename-extension": [1, { "extensions": [".tsx"] }], # follow the jest pattern and use js
          }
        }
        ]
    ESLINTRC

    create_file '.rubocop.yml', <<~RUBOCOP
      AllCops:
        Exclude:
          - 'node_modules/**/*'
          # EBS deployer folder - no need to peek
          - 'pkg/**/*'
          # core ruby stuff that doesn't pass - not going to change it
          - 'bin/**/*'
          - 'db/schema.rb'
          - lib/templates/active_record/model/model.rb # this is a weird template file so there isn't actually an issue here.
          - lib/templates/rails/**/*
          - lib/generators/component_generator.rb # copy and paste job - it's ugly
          - config/initializers/simple_form_bootstrap.rb
          - config/initializers/devise.rb # long line lengths for seeds...
          - lib/tasks/auto_annotate_models.rake # auto genned from gem
          - 'vendor/**/*' # exclude all the vendor stuff
          - data_import/notes.rb
        TargetRubyVersion: 2.6
        DisplayCopNames: true # so we know which cop to disable when it annoys us

      Metrics/LineLength:
        Max: 140

      Style/Documentation:
        Enabled: false

      Style/ClassAndModuleChildren:
        Enabled: false

      Metrics/BlockLength:
        ExcludedMethods:
          - included # for concerns - silly to alarm on those
        Exclude:
          - config/**/** # not worth beating up config file shape for this - dev/test/prod & routes files are biggest offenders and they feel weird split up
    RUBOCOP

    create_file '.stylelintrc', <<~STYLE
      {
        "extends": "stylelint-config-standard"
      }
    STYLE

    # removed test from eslint - re-add if jest gets added back in
    pkg_txt = <<-JSON
    "scripts": {
      "lint": "eslint \\"app/**/*.{tsx,js,jsx}\\" --fix",
      "lint:style": "stylelint \\"app/**/*.less\\" \\"app/**/*.css\\" \\"app/**/*.scss\\" \\"app/**/*.sass\\" --fix",
      "lint:ruby": "rubocop -a",
      "lint:ci": "npm-run-all -p lint lint:style",
      "test": "jest",
      "test:watch": "yarn test -- --watch",
      "test:ruby": "rails test",
      "validate": "npm-run-all -p -c lint lint:style lint:ruby",
      "validate:all": "npm-run-all -p lint lint:style lint:ruby test test:ruby",
      "test:suite": "npm-run-all -p test:ruby",
      "build:prod": "RAILS_ENV=production rails assets:precompile",
      "build:prod-profile": "PROFILE=true RAILS_ENV=production rails assets:precompile",
      "build:prod-prep": "RAILS_ENV=production rails assets:clobber"
    },
    JSON

    insert_into_file 'package.json', pkg_txt, before: "\n  \"dependencies\": {"

    # https://www.npmjs.com/package/eslint-config-react-app
    run 'yarn add typescript' # technically overkill but I didn't want to dig up none typescript linter configs
    run 'yarn add --dev eslint stylelint @typescript-eslint/eslint-plugin eslint-import-resolver-webpack @typescript-eslint/parser babel-eslint eslint-config-airbnb eslint-config-airbnb eslint-plugin-import eslint-plugin-jest eslint-plugin-jsx-a11y eslint-plugin-react eslint-plugin-react-hooks stylelint-config-standard'

    git_proxy_commit 'Setup styleguide and linters'

    gsub_file 'config/webpacker.yml', /localhost/, '0.0.0.0'
    gsub_file 'config/webpacker.yml', /hmr: false/, 'hmr: true'

    git_proxy_commit 'cleanup webpacker.yml'

    gsub_file 'app/javascript/packs/application.js', /require\("channels"\)/, '// require("channels")'

    run 'yarn validate'
    git_proxy_commit 'automatically format code with linters'
  end
end

def setup_commit_hooks
  after_bundle do
    pkg_txt = <<-JSON

  "husky": {
    "hooks": {
      "pre-commit": "yarn validate"
    }
  },
    JSON

    insert_into_file 'package.json', pkg_txt, before: "\n  \"dependencies\": {"

    run 'yarn add --dev husky npm-run-all'

    git_proxy_commit 'Install Husky'
  end
end

def enable_discard
  create_file 'config/initializers/timestamp_changes.rb', <<~TS
    # frozen_string_literal: true

    # http://millarian.com/rails/migration-timestamps-with-deleted_at-magic-field/ plus
    # http://stackoverflow.com/questions/20956526/rails-migration-generates-default-timestamps-created-at-updated-at-as-nullabl
    # = both being done and working fine.
    # Force t.timestamps to always be null: false & add discarded_at to default timestamps for tables
    module ActiveRecord
      module ConnectionAdapters
        module TimeStampChanges
          def timestamps(*args)
            options = args.extract_options!
            options[:null] = false
            super(*args, options)
            column(:discarded_at, :datetime) # Adds a discarded_at column when timestamps is called from a migration.
          end
        end
        TableDefinition.send(:prepend, TimeStampChanges)
      end
    end
  TS
end

def setup_oj
  create_file 'config/initializers/oj.rb', <<~OJ
    # frozen_string_literal: true

    # https://github.com/ohler55/oj/blob/57d4465bef8138fd4d83b239b77b1ef8883a4429/pages/Rails.md

    require 'oj'
    Oj.optimize_rails
  OJ
end

def create_database
  after_bundle do
    bundle_command 'exec rails db:create db:migrate'
    git_proxy_commit 'Create and migrate database'
  end
end

def fix_bundler_binstub
  after_bundle do
    run 'bundle binstubs bundler --force'
    git_proxy_commit "Fix bundler binstub\n\nhttps://github.com/rails/rails/issues/31193"
  end
end

def setup_newrelic
  inject_into_class 'app/controllers/application_controller.rb', 'ApplicationController' do
    <<-RB
      before_action :new_relic_user_info

      private

      def new_relic_user_info
        return unless current_user # just capturing info for logged in users right now

        ::NewRelic::Agent.add_custom_attributes(
          user_id: current_user.id,
          user_email: current_user.email
          # true_user_name: true_user&.id != current_user&.id ? true_user.name : nil
        )
      end
    RB
  end

  create_file 'config/newrelic.yml', <<~NR
    #
    # This file configures the New Relic Agent.  New Relic monitors Ruby, Java,
    # .NET, PHP, Python, Node, and Go applications with deep visibility and low
    # overhead.  For more information, visit www.newrelic.com.
    #
    # Generated XX XX, XXXX
    #
    # This configuration file is custom generated for <PROJECT_NAME>
    #
    # For full documentation of agent configuration options, please refer to
    # https://docs.newrelic.com/docs/agents/ruby-agent/installation-configuration/ruby-agent-configuration

    common: &default_settings
      # Required license key associated with your New Relic account.
      license_key: Setup New Account!

      # Your application name. Renaming here affects where data displays in New
      # Relic.  For more details, see https://docs.newrelic.com/docs/apm/new-relic-apm/maintenance/renaming-applications
      app_name: <PROJECT_NAME>

      # To disable the agent regardless of other settings, uncomment the following:
      # agent_enabled: false

      # Logging level for log/newrelic_agent.log
      log_level: info

      # capture job arguments for sidekiq jobs https://docs.newrelic.com/docs/agents/ruby-agent/background-jobs/sidekiq-instrumentation
      attributes.include: job.sidekiq.args.*

      # capture controller params for reproduction https://docs.newrelic.com/docs/agents/ruby-agent/configuration/ruby-agent-configuration#capture_params
      capture_params: true

      # capture the actual sql that is slow rather than the obfuscated stuff
      slow_sql.record_sql: raw # https://docs.newrelic.com/docs/agents/ruby-agent/configuration/ruby-agent-configuration#slow_sql
      transaction_tracer.record_sql: raw # https://docs.newrelic.com/docs/agents/ruby-agent/configuration/ruby-agent-configuration#transaction_tracer

      # https://docs.newrelic.com/docs/agents/ruby-agent/installation-configuration/ignoring-specific-transactions#ignore-rails
      # ignore health check URLs to keep our new relic throughput clean & more likely to return error messages
      rules:
        ignore_url_regexes: ["^/health_check"]


    # Environment-specific settings are in this section.
    # RAILS_ENV or RACK_ENV (as appropriate) is used to determine the environment.
    # If your application has other named environments, configure them here.
    development:
      <<: *default_settings
      app_name: <PROJECT_NAME> (Development)
      developer_mode: true

    test:
      <<: *default_settings
      # It doesn't make sense to report to New Relic from automated test runs.
      monitor_mode: false

    staging:
      <<: *default_settings
      app_name: <PROJECT_NAME> (Staging)

    production:
      <<: *default_settings
  NR

  git_proxy_commit 'Setup Newrelic'
end

def setup_readme
  remove_file 'README.md'
  get "#{REPOSITORY_PATH}/templates/README.md", 'README.md'
  unless $using_sidekiq
    gsub_file 'README.md', /### Sidekiq.*###/, '###'
    gsub_file 'README.md', /^.*Sidekiq.*\n/, ''
  end

  git_proxy_commit 'Add README'
end

def setup_testing
  after_bundle do
    bundle_command 'exec rails generate rspec:install'
    run 'bundle binstubs rspec-core'
    git_proxy_commit 'RSpec install'

    create_file 'spec/support/chromedriver.rb', <<~RB
      require 'selenium/webdriver'

      Capybara.register_driver :chrome do |app|
        Capybara::Selenium::Driver.new(app, browser: :chrome)
      end

      Capybara.register_driver :headless_chrome do |app|
        capabilities = Selenium::WebDriver::Remote::Capabilities.chrome(
          chromeOptions: { args: %w[headless disable-gpu] }
        )

        Capybara::Selenium::Driver.new(
          app,
          browser: :chrome,
          desired_capabilities: capabilities
        )
      end

      Capybara.javascript_driver = :headless_chrome
    RB

    create_file 'spec/support/shoulda_matchers.rb', <<-SH
    Shoulda::Matchers.configure do |config|
      config.integrate do |with|
        with.test_framework :rspec
        with.library :rails
      end
    end
    SH

    create_file 'spec/lint_spec.rb', <<~RB
      # consider switching to rake task in the future: https://github.com/thoughtbot/factory_bot/blob/master/GETTING_STARTED.md#linting-factories
      require 'rails_helper'
      RSpec.describe "Factories" do
        it 'lints successfully' do
          FactoryBot.lint
        end
      end
    RB

    uncomment_lines 'spec/rails_helper.rb', /Dir\[Rails\.root\.join/

    gsub_file 'spec/spec_helper.rb', "=begin\n", ''
    gsub_file 'spec/spec_helper.rb', "=end\n", ''

    comment_lines 'spec/rails_helper.rb', 'config.fixture_path ='

    insert_into_file 'spec/rails_helper.rb',
                     "  config.include FactoryBot::Syntax::Methods\n\n",
                     after: "RSpec.configure do |config|\n"

    insert_into_file 'spec/rails_helper.rb',
                     "require \"capybara/rails\"\n",
                     after: "Add additional requires below this line. Rails is not loaded until this point!\n"

    git_proxy_commit 'Finish setting up testing'
  end
end

def main_config_files
  insert_into_file 'config/database.yml', after: "default: &default\n" do
    <<-YML
  reaping_frequency: <%= ENV["DB_REAP_FREQ"] || 10 %> # https://devcenter.heroku.com/articles/concurrency-and-database-connections#bad-connections
  connect_timeout: 1 # raises PG::ConnectionBad
  checkout_timeout: 1 # raises ActiveRecord::ConnectionTimeoutError
  variables:
    statement_timeout: 10000 # manually override on a per-query basis
    YML
  end

  uncomment_lines 'config/puma.rb', 'workers ENV.fetch'
  uncomment_lines 'config/puma.rb', /preload_app!$/

  create_file 'Procfile', <<~PROCFILE
    web: bundle exec puma -C config/puma.rb
    release: bundle exec rake db:migrate
  PROCFILE

  create_file '.editorconfig', <<~EDITORCONFIG
    # This file is for unifying the coding style for different editors and IDEs
    # editorconfig.org

    root = true

    [*]
    charset = utf-8
    trim_trailing_whitespace = true
    insert_final_newline = true
    indent_style = space
    indent_size = 2
    end_of_line = lf
  EDITORCONFIG

  append_file '.gitignore', <<~GITIGNORE

    spec/examples.txt

    .env.development.local
    .env.local
    .env.test.local

    /.idea/
    /package-lock.json
  GITIGNORE

  create_file '.env', <<~ENV
    WEB_CONCURRENCY=1 # set to 1 in dev most of the time for easy testing
    SEND_EMAIL=false # change to true to send email via sendgrid
  ENV

  git_proxy_commit 'Setup config files'
end

def heroku_ci_file
  create_file 'app.json', <<~APPJSON
    {
      "environments": {
        "test": {
          "addons": ["heroku-redis:hobby-dev", "heroku-postgresql:in-dyno"],
          "env": {
            "RAILS_ENV": "test",
            "DISABLE_SPRING": "true",
            "CAPYBARA_WAIT_TIME": "10"
          },
          "scripts": {
            "test-setup": "bundle exec rails assets:precompile",
            "test": "yarn test:suite",
            "brakeman": "bundle exec brakeman -w2 --exit-on-warn",
            "bundle-audit": "bundle exec bundle audit check --update --ignore CVE-2015-9284",
            "bundle-leak": "bundle exec bundle leak check --update"
          },
          "formation": {
            "test": {
              "quantity": 1
            }
          },
          "buildpacks": [
            { "url": "heroku/nodejs" },
            { "url": "heroku/ruby" },
            { "url": "https://github.com/heroku/heroku-buildpack-google-chrome" },
            { "url": "https://github.com/heroku/heroku-buildpack-chromedriver" }
          ]
        }
      }
    }
  APPJSON

  create_file 'lib/tasks/scheduler.rake',
              <<~SCHEDULER
                # frozen_string_literal: true

                desc 'This task is called by the Heroku scheduler add-on'

                task db_maintenance: :environment do
                  start_time = Time.zone.now
                  PgHero.capture_space_stats
                  PgHero.clean_query_stats

                  # https://www.postgresql.org/docs/9.4/static/routine-vacuuming.html#VACUUM-FOR-SPACE-RECOVERY
                  ActiveRecord::Base.connection.execute('vacuum analyze') unless Rails.env.test? # can't run vacuum inside of a transaction block
                  # it isn't worth breaking this spec out to some magic separate test case to test that this is working so we'll just bypass this here.

                  # skipping reindex operation because it requires a lock on the table - most of our tables will run fast but the big
                  # boys tables have the chance of impacting customers so we'll skip this now until it becomes
                  # a problem. - https://www.postgresql.org/docs/9.4/static/sql-reindex.html
                  # ActiveRecord::Base.connection.execute("reindex database \#{ActiveRecord::Base.connection.current_database}")

                  puts "runtime of \#{(Time.zone.now - start_time).to_i}"
                end
              SCHEDULER
end

def assert_minimum_rails_and_ruby_version!
  requirement = Gem::Requirement.new(RAILS_REQUIREMENT)
  rails_version = Gem::Version.new(Rails::VERSION::STRING)
  return if requirement.satisfied_by?(rails_version)

  prompt = "This template requires Rails #{RAILS_REQUIREMENT}. "\
           "You are using #{rails_version}. Continue anyway?"
  exit 1 if no?(prompt)

  requirement = Gem::Requirement.new(RUBY_REQUIREMENT)
  ruby_version = Gem::Version.new(RUBY_VERSION)
  return if requirement.satisfied_by?(ruby_version)

  prompt = "This template requires Ruby #{RUBY_REQUIREMENT}. "\
           "You are using #{ruby_version}. Continue anyway?"
  exit 1 if no?(prompt)
end

def setup_generators
  initializer 'generators.rb',
              <<~EOF
                Rails.application.config.generators do |g|
                  # use UUIDs by default
                  g.orm :active_record, primary_key_type: :uuid

                  # limit default generation
                  g.test_framework(
                    :rspec,
                    fixtures: true,
                    view_specs: false,
                    controller_specs: false,
                    routing_specs: false,
                    request_specs: false,
                  )

                  # prevent generating js/css/helper files
                  g.assets false
                  g.helper false
                  g.jbuilder false

                  g.fixture_replacement :factory_bot, dir: 'spec/factories'
                  g.factory_bot suffix: 'factory'
                end
              EOF

  git_proxy_commit 'Configured generators (UUIDs, less files)'
end

def generate_tmp_dirs
  # unclear why this is needed, but `heroku local` fails without it
  # "No such file or directory @ rb_sysopen - tmp/pids/server.pid"
  empty_directory 'tmp/pids'
end

run_template!

run_after_bundle_callbacks if no?('Is this a new application?')
