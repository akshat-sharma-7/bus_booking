class ApplicationController < ActionController::Base
  include Authentication
  allow_browser versions: :modern

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  private

  def render_not_found
    redirect_to root_path, alert: "The page you were looking for is no longer available."
  end
end
