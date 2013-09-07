module CanCan

  # This module adds the accessible_by class method to a model. It is included in the model adapters.
  module ModelAdditions
    module ClassMethods
      # Returns a scope which fetches only the records that the passed ability
      # can perform a given action on. The action defaults to :index. This
      # is usually called from a controller and passed the +current_ability+.
      #
      #   @articles = Article.accessible_by(current_ability)
      #
      # Here only the articles which the user is able to read will be returned.
      # If the user does not have permission to read any articles then an empty
      # result is returned. Since this is a scope it can be combined with any
      # other scopes or pagination.
      #
      # An alternative action can optionally be passed as a second argument.
      #
      #   @articles = Article.accessible_by(current_ability, :update)
      #
      # Here only the articles which the user can update are returned.
      def accessible_by(ability, action = :index)
        ability.model_adapter(self, action).database_records
      end

      attr_writer :has_polymorphic_proxy_model
      attr_accessor :polymorphic_proxy_model_field, :has_polymorphic_proxy_model

      # Sometimes, you want a model to be visible or not based on the visibility of an associated
      # model. E.g. PaperTrail::version or PublicActivity::Activity
      def has_polymorphic_proxy_model_on(polymorphic_association_name)
        self.has_polymorphic_proxy_model = true
        self.polymorphic_proxy_model_field = polymorphic_association_name
      end

      def has_polymorphic_proxy_model?
        self.has_polymorphic_proxy_model.present? && self.has_polymorphic_proxy_model
      end
    end

    def self.included(base)
      base.extend ClassMethods
    end
  end
end
