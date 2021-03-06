class Roda
  module RodaPlugins
    module Rodauth
      VerifyAccount = Feature.define(:verify_account) do
        depends :login, :create_account
        route 'verify-account'
        notice_flash "Your account has been verified"
        view 'verify-account', 'Verify Account'
        additional_form_tags
        after
        button 'Verify Account'
        redirect

        auth_value_methods(
          :no_matching_verify_account_key_message,
          :verify_account_autologin?,
          :verify_account_email_subject,
          :verify_account_email_sent_redirect,
          :verify_account_email_sent_notice_flash,
          :verify_account_id_column,
          :verify_account_key_column,
          :verify_account_key_param,
          :verify_account_key_value,
          :verify_account_table
        )
        auth_methods(
          :account_from_verify_account_key,
          :create_verify_account_key,
          :create_verify_account_email,
          :remove_verify_account_key,
          :send_verify_account_email,
          :verify_account,
          :verify_account_email_body,
          :verify_account_email_link,
          :verify_account_key_insert_hash
        )

        get_block do |r, auth|
          if key = r[auth.verify_account_key_param]
            if auth._account_from_verify_account_key(key)
              auth.verify_account_view
            else
              auth.set_redirect_error_flash auth.no_matching_verify_account_key_message
              r.redirect auth.require_login_redirect
            end
          end
        end

        post_block do |r, auth|
          if login = r[auth.login_param]
            if auth._account_from_login(login.to_s) && !auth.open_account? && auth.verify_account_email_resend
              auth.set_notice_flash auth.verify_account_email_sent_notice_flash
              r.redirect auth.verify_account_email_sent_redirect
            end
          elsif key = r[auth.verify_account_key_param]
            if auth._account_from_verify_account_key(key.to_s)
              auth.transaction do
                auth.verify_account
                auth.remove_verify_account_key
                auth.after_verify_account
              end
              if auth.verify_account_autologin?
                auth.update_session
              end
              auth.set_notice_flash auth.verify_account_notice_flash
              r.redirect(auth.verify_account_redirect)
            end
          end
        end

        def before_login_attempt
          unless open_account?
            set_error_flash attempt_to_login_to_unverified_account_notice_message
            response.write resend_verify_account_view
            request.halt
          end
          super
        end

        def generate_verify_account_key_value
          @verify_account_key_value = random_key
        end

        def create_verify_account_key
          ds = db[verify_account_table].where(verify_account_id_column=>account_id_value)
          transaction do
            ds.insert(verify_account_key_insert_hash) if ds.empty?
          end
        end

        def verify_account_key_insert_hash
          {verify_account_id_column=>account_id_value, verify_account_key_column=>verify_account_key_value}
        end

        def remove_verify_account_key
          db[verify_account_table].where(verify_account_id_column=>account_id_value).delete
        end

        def verify_account
          account.set(account_status_id=>account_open_status_value).save_changes(:raise_on_failure=>true)
        end

        def verify_account_resend_additional_form_tags
          nil
        end

        def verify_account_resend_button
          'Send Verification Email Again'
        end

        def verify_account_email_resend
          if @verify_account_key_value = db[verify_account_table].where(verify_account_id_column=>account_id_value).get(verify_account_key_column)
            send_verify_account_email
            true
          end
        end

        def attempt_to_create_unverified_account_notice_message
          "The account you tried to create is currently awaiting verification"
        end

        def attempt_to_login_to_unverified_account_notice_message
          "The account you tried to login with is currently awaiting verification"
        end

        def resend_verify_account_view
          view('verify-account-resend', 'Resend Verification Email')
        end

        def verify_account_email_sent_notice_flash
          "An email has been sent to you with a link to verify your account"
        end
        
        def create_account_notice_flash
          verify_account_email_sent_notice_flash
        end

        def after_create_account
          generate_verify_account_key_value
          create_verify_account_key
          send_verify_account_email
        end

        def new_account(login)
          if _account_from_login(login)
            set_error_flash attempt_to_create_unverified_account_notice_message
            response.write resend_verify_account_view
            request.halt
          end
          super
        end

        def no_matching_verify_account_key_message
          "invalid verify account key"
        end

        def _account_from_verify_account_key(key)
          @account = account_from_verify_account_key(key)
        end

        def account_from_verify_account_key(key)
          id, key = key.split('_', 2)
          return unless id && key

          id_column = verify_account_id_column
          id = id.to_i

          return unless actual = db[verify_account_table].
            where(id_column=>id).
            get(verify_account_key_column)

          return unless timing_safe_eql?(key, actual)

          @account = account_model.where(account_status_id=>account_unverified_status_value, account_id=>id).first
        end
        
        def verify_account_email_sent_redirect
          require_login_redirect
        end

        def verify_account_table
          :account_verification_keys
        end

        def verify_account_id_column
          :id
        end

        def verify_account_key_column
          :key
        end

        def account_initial_status_value
          account_unverified_status_value
        end

        attr_reader :verify_account_key_value

        def create_verify_account_email
          create_email(verify_account_email_subject, verify_account_email_body)
        end

        def send_verify_account_email
          create_verify_account_email.deliver!
        end

        def verify_account_email_body
          render('verify-account-email')
        end

        def verify_account_email_link
          "#{request.base_url}#{prefix}/#{verify_account_route}?#{verify_account_key_param}=#{account_id_value}_#{verify_account_key_value}"
        end

        def verify_account_email_subject
          'Verify Account'
        end

        def verify_account_key_param
          'key'
        end

        def verify_account_autologin?
          false
        end

        def after_close_account
          super
          db[verify_account_table].where(reset_password_id_column=>account_id_value).delete
        end
      end
    end
  end
end

