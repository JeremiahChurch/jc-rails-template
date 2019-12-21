# frozen_string_literal: true

require 'test/unit'
require 'open3'

class TestGettingStarted < Test::Unit::TestCase
  def setup
    puts 'installing rails'
    assert(system('gem install rails -v 6.0.2 --no-document'), 'install rails')
    assert(system('mkdir -p tmp'), 'create tmp directory')

    puts "which: #{`which rails`}"
    puts "rails version: #{`rails --version`}"
  end

  def test_build_succeeds
    Dir.chdir('tmp') do
      assert(system('rm -rf ./Foobar'), 'existing rails app is removed')

      cmd = '../test/rails_new'

      puts 'running:'
      puts "$ #{cmd} (#{`pwd`.strip})"

      result = system(cmd)

      assert(result, 'command exits with zero exit status')
    end
  end

  def test_specs_pass
    Dir.chdir('tmp/Foobar') do
      assert(system('bundle exec rspec spec'), 'tests pass')
    end
  end

  def test_rails_console
    Dir.chdir('tmp/Foobar') do
      assert(system("echo 'puts \"hello!\"' | bundle exec rails c"), 'rails console works')
    end
  end
end
