class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Covers every user-facing `.find` in this app (Trip, Booking, ...) — a
  # deleted/nonexistent record shows a normal flash-and-redirect instead of
  # Rails' raw exception page. Deliberately scoped to this one exception
  # class, not a blanket `rescue_from StandardError`, so real bugs still
  # surface normally.
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  private

  def render_not_found
    redirect_to root_path, alert: "The page you were looking for is no longer available."
  end
end
