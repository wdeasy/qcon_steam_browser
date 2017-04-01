class ContactMailer < ActionMailer::Base
  default from: "byoc ninja <#{ENV["EMAIL_USERNAME"]}>"
  default to: "byoc ninja <#{ENV["EMAIL_USERNAME"]}>"

  def new(message)
    @message = message

    mail from: "#{message.name} <#{message.email}>"
    mail subject: "BYOC.NINJA >> Message from #{message.name} <#{message.email}>"
  end
end
