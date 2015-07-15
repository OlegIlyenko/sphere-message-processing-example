Q = require 'q'
{_} = require 'underscore'
_s = require 'underscore.string'
{MessageProcessing, LoggerFactory} = require 'sphere-message-processing'
{loadFile, EmailSender} = require './util'

module.exports = MessageProcessing.builder()
.processorName "send-email-on-order-import"
.optimistDemand ['smtpConfig', "smtpFrom"]
.optimistExtras (o) ->
  o.describe('smtpFrom', 'A sender of the emails.')
  .describe('smtpConfig', 'SMTP Config JSON file: https://github.com/andris9/Nodemailer#setting-up-smtp')
.messageType 'order'
.build (argv, stats, requestQueue, cc, rootLogger) ->
  logger = LoggerFactory.getLogger "send-email-on-order-import", rootLogger

  loadFile(argv.smtpConfig)
  .then (smtpConfig) ->
    emailSender = new EmailSender(smtpConfig, logger, stats)

    processOrderImport = (sourceInfo, msg) ->
      emails = sourceInfo.sphere.projectProps['email']

      if not emails? or (_.isString(emails) and _s.isBlank(emails))
        emails = []
      else if _.isString(emails)
        emails = [emails]

      if not _.isEmpty(emails)
        mail =
          from: argv.smtpFrom
          subject: "New order imported: #{msg.order.orderNumber or msg.order.id}"
          text: "New order! Yay!"

        if not _.isEmpty(emails)
          mail.to = emails.join(", ")

        console.info(argv.smtpFrom, emails)
        emailSender.sendMail sourceInfo, msg, emails, [], mail
        .then ->
          {processed: true, processingResult: {emails: emails}}
      else
        Q({processed: true, processingResult: {ignored: true, reason: "no TO"}})

    (sourceInfo, msg) ->
      if msg.resource.typeId is 'order' and msg.type is 'OrderImported'
        processOrderImport sourceInfo, msg
        .fail (error) ->
          Q.reject new Error("Error! Cause: #{error.stack}")
      else
        Q({processed: true, processingResult: {ignored: true}})