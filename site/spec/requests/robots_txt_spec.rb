require 'rails_helper'

RSpec.describe 'GET /robots.txt' do
  context 'when on API Entreprise' do
    before { host! 'entreprise.api.localtest.me' }

    it 'forbids every crawler outside production' do
      get '/robots.txt'

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("User-agent: *\nDisallow: /\n")
    end

    it 'exposes the sitemap in production' do
      allow(Rails.env).to receive(:production?).and_return(true)

      get '/robots.txt'

      expect(response.body).to include('Sitemap: http://entreprise.api.gouv.fr/sitemaps/api-entreprise/sitemap.xml.gz')
      expect(response.body).to include('Disallow: /compte/')
    end
  end

  context 'when on API Particulier' do
    before { host! 'particulier.api.localtest.me' }

    it 'forbids every crawler outside production' do
      get '/robots.txt'

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("User-agent: *\nDisallow: /\n")
    end

    it 'exposes the sitemap in production' do
      allow(Rails.env).to receive(:production?).and_return(true)

      get '/robots.txt'

      expect(response.body).to include('Sitemap: http://particulier.api.gouv.fr/sitemaps/api-particulier/sitemap.xml.gz')
    end
  end
end
