module CanCan
  module ModelAdapters
    class ActiveRecordAdapter < AbstractAdapter
      def self.for_class?(model_class)
        model_class <= ActiveRecord::Base
      end

      def self.override_condition_matching?(subject, name, value)
        name.kind_of?(MetaWhere::Column) if defined? MetaWhere
      end

      def self.matches_condition?(subject, name, value)
        subject_value = subject.send(name.column)
        if name.method.to_s.ends_with? "_any"
          value.any? { |v| meta_where_match? subject_value, name.method.to_s.sub("_any", ""), v }
        elsif name.method.to_s.ends_with? "_all"
          value.all? { |v| meta_where_match? subject_value, name.method.to_s.sub("_all", ""), v }
        else
          meta_where_match? subject_value, name.method, value
        end
      end

      def self.meta_where_match?(subject_value, method, value)
        case method.to_sym
        when :eq      then subject_value == value
        when :not_eq  then subject_value != value
        when :in      then value.include?(subject_value)
        when :not_in  then !value.include?(subject_value)
        when :lt      then subject_value < value
        when :lteq    then subject_value <= value
        when :gt      then subject_value > value
        when :gteq    then subject_value >= value
        when :matches then subject_value =~ Regexp.new("^" + Regexp.escape(value).gsub("%", ".*") + "$", true)
        when :does_not_match then !meta_where_match?(subject_value, :matches, value)
        else raise NotImplemented, "The #{method} MetaWhere condition is not supported."
        end
      end

      # Returns conditions intended to be used inside a database query. Normally you will not call this
      # method directly, but instead go through ModelAdditions#accessible_by.
      #
      # If there is only one "can" definition, a hash of conditions will be returned matching the one defined.
      #
      #   can :manage, User, :id => 1
      #   query(:manage, User).conditions # => { :id => 1 }
      #
      # If there are multiple "can" definitions, a SQL string will be returned to handle complex cases.
      #
      #   can :manage, User, :id => 1
      #   can :manage, User, :manager_id => 1
      #   cannot :manage, User, :self_managed => true
      #   query(:manage, User).conditions # => "not (self_managed = 't') AND ((manager_id = 1) OR (id = 1))"
      #
      def conditions
        if @rules.size == 1 && @rules.first.base_behavior
          # Return the conditions directly if there's just one definition
          tableized_conditions(@rules.first.conditions).dup
        else
          @rules.reverse.inject(false_sql) do |sql, rule|
            merge_conditions(sql, tableized_conditions(rule.conditions).dup, rule.base_behavior)
          end
        end
      end

      def tableized_conditions(conditions, model_class = @model_class)
        return conditions unless conditions.kind_of? Hash
        conditions.inject({}) do |result_hash, (name, value)|
          if value.kind_of? Hash
            value = value.dup
            association_class = model_class.reflect_on_association(name).class_name.constantize
            nested = value.inject({}) do |nested,(k,v)|
              if v.kind_of? Hash
                value.delete(k)
                nested[k] = v
              else
                name = model_class.reflect_on_association(name).table_name.to_sym
                result_hash[name] = value
              end
              nested
            end
            result_hash.merge!(tableized_conditions(nested,association_class))
          elsif @model_class.has_polymorphic_proxy_model?
            result_hash["#{model_class.table_name}.#{name}"] = value
          else
            result_hash[name] = value
          end
          result_hash
        end
      end

      # Returns the associations used in conditions for the :joins option of a search.
      # See ModelAdditions#accessible_by
      def joins
        joins_hash = {}
        @rules.each do |rule|
          merge_joins(joins_hash, rule.associations_hash)
        end
        clean_joins(joins_hash) unless joins_hash.empty?
      end


      # The intention is to use the WHERE conditions that are passed to the can() calls on the model tables that are joined
      # To Version, not Version itself.
      # Version has a polymorphic association called item, which holds the models.
      # The SQL fragments start with the raw table name like this: "narratives.id IN (SELECT ...)"
      def database_records
        if @model_class.has_polymorphic_proxy_model?

          # As it's a left join, we need to lump the WHERE clauses together, otherwise it'll treat them as optional.
          mergeable_conditions = @rules.select { |rule| rule.unmergeable? }.blank?
          if mergeable_conditions
            # Join the trackable model polymorphic tables to the activities table. The SQL fragments then act on the
            # left-joined tables, rather than the target model table.
            models_to_join_with = @rules.collect { |rule| rule.subjects[0] }.uniq
            model_relation_with_joined_tables = models_to_join_with.inject(@model_class) do |relation, model_class|
              relation.joins("LEFT JOIN #{model_class.table_name} ON #{@model_class.table_name}.#{@model_class.polymorphic_proxy_model_field}_type = '#{model_class}' AND #{@model_class.table_name}.#{@model_class.polymorphic_proxy_model_field}_id = #{model_class.table_name}.id")
            end
            model_relation_with_joined_tables.where(conditions_for_polymorphic_proxy_model)
          else
            raise 'Cannot merge the conditions for CanCan'
          end
        else
          if override_scope
            @model_class.scoped.merge(override_scope)
          elsif @model_class.respond_to?(:where) && @model_class.respond_to?(:joins)
            mergeable_conditions = @rules.select { |rule| rule.unmergeable? }.blank?
            if mergeable_conditions
              @model_class.where(conditions).joins(joins)
            else
              @model_class.where(*(@rules.map(&:conditions))).joins(joins)
            end
          else
            @model_class.scoped(:conditions => conditions, :joins => joins)
          end
        end

      end

      private

      def override_scope
        conditions = @rules.map(&:conditions).compact
        if defined?(ActiveRecord::Relation) && conditions.any? { |c| c.kind_of?(ActiveRecord::Relation) }
          if conditions.size == 1
            conditions.first
          else
            rule = @rules.detect { |rule| rule.conditions.kind_of?(ActiveRecord::Relation) }
            raise Error, "Unable to merge an Active Record scope with other conditions. Instead use a hash or SQL for #{rule.actions.first} #{rule.subjects.first} ability."
          end
        end
      end

      def merge_conditions(sql, conditions_hash, behavior)
        if conditions_hash.blank?
          behavior ? true_sql : false_sql
        else
          conditions = sanitize_sql(conditions_hash)
          case sql
          when true_sql
            behavior ? true_sql : "not (#{conditions})"
          when false_sql
            behavior ? conditions : false_sql
          else
            behavior ? "(#{conditions}) OR (#{sql})" : "not (#{conditions}) AND (#{sql})"
          end
        end
      end

      def false_sql
        sanitize_sql(['?=?', true, false])
      end

      def true_sql
        sanitize_sql(['?=?', true, true])
      end

      def sanitize_sql(conditions)
        @model_class.send(:sanitize_sql, conditions)
      end

      # Takes two hashes and does a deep merge.
      def merge_joins(base, add)
        add.each do |name, nested|
          if base[name].is_a?(Hash)
            merge_joins(base[name], nested) unless nested.empty?
          else
            base[name] = nested
          end
        end
      end

      # Removes empty hashes and moves everything into arrays.
      def clean_joins(joins_hash)
        joins = []
        joins_hash.each do |name, nested|
          joins << (nested.empty? ? name : {name => clean_joins(nested)})
        end
        joins
      end



      # Makes sure that the string of OR conditions are wrapped up so that they only apply to models they matter for.
      # These models have been linked to the target model with a left-join, so we want to make sure that if the
      # SQL in the rule works, the left-joined id column is also no null for that model.
      # Without this bit, an empty sql conditions bit will lead to a "true = true" that will match everything, whereas we
      # only want it to match that model.
      def conditions_for_polymorphic_proxy_model
        if @rules.size == 1 && @rules.first.base_behavior
          # Return the conditions directly if there's just one definition
          wrap_condition_in_table_specific_not_null @rules.first, tableized_conditions(@rules.first.conditions, @rules.first.subjects.first).dup
        else
          @rules.reverse.inject('') do |sql, rule|
            merge_conditions_for_polymorphic_proxy(sql, tableized_conditions(rule.conditions, rule.subjects.first).dup, rule)
          end
        end
      end

      def wrap_condition_in_table_specific_not_null(rule, condition)
        "(#{rule.subjects[0].table_name}.id IS NOT NULL AND (#{sanitize_sql(condition)}))"
      end

      def merge_conditions_for_polymorphic_proxy(sql, conditions_hash, rule)
        behavior = rule.base_behavior
        if conditions_hash.blank?
          blank_sql = behavior ? true_sql : false_sql
          conditions = wrap_condition_in_table_specific_not_null rule, blank_sql
        else
          conditions = wrap_condition_in_table_specific_not_null rule, sanitize_sql(conditions_hash)
        end

        case sql
          when ''
            behavior ? conditions : "NOT #{conditions}"
          else
            behavior ? "#{conditions} OR #{sql}" : "NOT #{conditions} AND #{sql}"
        end
      end
    end
  end
end

ActiveRecord::Base.class_eval do
  include CanCan::ModelAdditions
end
