# <PROJECT_NAME>

### Services used

- Postgresql
- Newrelic
- Redis (required for Sidekiq)

### Local Setup Guide

Important note: Please setup your local code editor with [EditorConfig](https://editorconfig.org/) for code normalization

To setup the project for your local environment, please run the included script:

```bash
$ bin/setup
```

### Running Tests

This project uses RSpec for testing. To run tests:

```bash
$ yarn test:suite
```

For javascript integration testing, we use Google Chromedriver. You may need to `brew install chromedriver` to get this working!

### Heroku configuration

This project is served from Heroku.

### Deployment Information

### Sidekiq

This project uses Sidekiq to run background jobs and ActiveJob is configured to use Sidekiq. It is recommended to use ActiveJob to create jobs for simplicity, unless the performance overhead of ActiveJob is an issue.

Remember to follow the [Sidekiq Best Practices](https://github.com/mperham/sidekiq/wiki/Best-Practices), especially making jobs idempotent and transactional. If you are using ActiveJob, the first best practice is _less_ relevant because of Rails GlobalID.

### Email

This project is configured to use sendgrid email for sendgrid see https://github.com/eddiezane/sendgrid-actionmailer for more details

### Coding Style

AirBnB Code quality ESLint can be run via `yarn lint` for the react components - `rubocop -a` for rails. You can do it all at once with `yarn validate`

a pre commit hook will be run that to make sure everything is good before committing code - this can be bypassed by running `--no-verify` on your commit

see [package.json](package.json) for info on how to change its setup.

__NO LOGIC IN RAILS VIEWS__ it's hard to test and it's a code smell. put it in a helper no matter how small. if you see some, refactor it.

[h]: https://github.com/typicode/husky

Making changes to the linter setup? Please share your fixes and make a PR to the [template](https://github.com/JeremiahChurch/jc-rails-template) so future projects may benefit.

### Important rake tasks

### Scheduled tasks

### Important ENV variables

Configuring Servers:

```
WEB_CONCURRENCY - Number of Puma workers
RAILS_MAX_THREADS - Number of threads per Puma worker
SIDEKIQ_CONCURRENCY - Number of Sidekiq workers
```

rack-timeout:

```
RACK_TIMEOUT_SERVICE_TIMEOUT
RACK_TIMEOUT_WAIT_TIMEOUT
RACK_TIMEOUT_WAIT_OVERTIME
RACK_TIMEOUT_SERVICE_PAST_WAIT
```

refer to [rack-timeout][rt] for default values

[rt]: https://github.com/sharpstone/rack-timeout#configuring

Note that this project uses [dotenv](https://github.com/bkeepers/dotenv) to load `.env` files. Use `.env.development` and `.env.test` to setup _shared_ ENV variables for development and test, and use `.env` files ending in `.local` for variables specific to you.

### URLs

 Prod URL 
 
 CI 
 
 Prod deploy 
 
 Prod monitoring 

