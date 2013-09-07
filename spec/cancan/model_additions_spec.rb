require "spec_helper"

describe CanCan::ModelAdditions do

  if ENV["MODEL_ADAPTER"].nil? || ENV["MODEL_ADAPTER"] == "active_record"

    it "adds the has_polymorphic_proxy_model_on method" do
      ActiveRecord::Base.respond_to?(:has_polymorphic_proxy_model_on).should be_true
    end

    it "adds the has_polymorphic_proxy_model? method" do
      ActiveRecord::Base.respond_to?(:has_polymorphic_proxy_model?).should be_true
    end

    it "adds the has_polymorphic_proxy_model= method" do
      ActiveRecord::Base.respond_to?(:has_polymorphic_proxy_model=).should be_true
    end

    it "adds the polymorphic_proxy_model_field method" do
      ActiveRecord::Base.respond_to?(:polymorphic_proxy_model_field).should be_true
    end

    it "adds the polymorphic_proxy_model_field= method" do
      ActiveRecord::Base.respond_to?(:polymorphic_proxy_model_field=).should be_true
    end
  end


end