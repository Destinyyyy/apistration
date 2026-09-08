class RobotsTxt
  PRODUCTION_TEMPLATE_PATH = 'config/seo/robots.txt'.freeze
  NON_PRODUCTION_TEMPLATE_PATH = 'config/seo/robots_non_production.txt'.freeze

  def initialize(app)
    @app = app
  end

  def call(_env)
    [200, { 'Content-Type' => 'text/plain' }, [body]]
  end

  private

  attr_reader :app

  def body
    return Rails.root.join(NON_PRODUCTION_TEMPLATE_PATH).read unless Rails.env.production?

    format(Rails.root.join(PRODUCTION_TEMPLATE_PATH).read, app:)
  end
end
