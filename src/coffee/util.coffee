Q = require 'q'
fs = require 'q-io/fs'
http = require 'q-io/http'
{Repeater, TaskQueue} = require 'sphere-message-processing'
nodemailer = require "nodemailer"

stdFs = require 'fs'
_ = require('underscore')._
_s = require 'underscore.string'

# nodemailer has a lot of bugs, so we need this class to work around them
class EmailSender
  constructor: (smtpConfig, @logger, @stats) ->
    @sendMailQueue = new TaskQueue @stats, {maxParallelTasks: 1}
    @sendMailRepeater = new Repeater {attempts: 2, timeout: 20000}
    @smtpConfigObj = JSON.parse(smtpConfig)

  createTransport: ->
    nodemailer.createTransport "SMTP", @smtpConfigObj

  # use it for dangerous operations that potentially can not call the callback
  withTimeout: (options) =>
    {timeout, task, onTimeout} = options
    start = Date.now()
    d = Q.defer()

    canceled = false

    timeoutFn = () ->
      onTimeout()
      .then (obj) ->
        d.resolve obj
      .fail (error) ->
        d.reject error
      .done()

      canceled = true

    timeoutObject = setTimeout timeoutFn, timeout

    task()
    .then (obj) ->
      if not canceled
        d.resolve obj
    .fail (error) ->
      if not canceled
        d.reject error
    .finally () =>
      if not canceled
        clearTimeout(timeoutObject)
      else
        end = Date.now()
        @logger.error "Nodemailer returned the respose after the timeout #{timeout}ms! It took it #{end - start}ms to complete."
    .done()

    d.promise

  closeTransport: (t) ->
    d = Q.defer()

    t.close ->
      d.resolve()

    d.promise

  sendMail: (sourceInfo, msg, emails, bccEmails, mail) ->
    transport = null

    @sendMailRepeater.execute
      recoverableError: (e) -> true
      task: =>
        @withTimeout
          timeout: 300000
          task: =>
            send = (t) ->
              d = Q.defer()

              t.sendMail mail, (error, resp) ->
                if error
                  d.reject error
                else
                  d.resolve {processed: true, processingResult: {emails: emails, bccEmails: bccEmails}}

              d.promise

            @sendMailQueue.addTask =>
              transport = @createTransport()
              send transport
              .finally =>
                @closeTransport transport
          onTimeout: =>
            reject = Q.reject new Error("Timeout during mail sending! Nodemailer haven't called the callback within 5 minutes during processing of the message #{msg.id} in project #{sourceInfo.sphere.getSourceInfo().prefix}")

            if transport?
              @closeTransport transport
              .then -> reject
            else
              reject

module.exports =
  EmailSender: EmailSender

  # load file from local FS or URL and returns a string promise
  loadFile: (fileOrUrl) ->
    if not fileOrUrl? or _s.isBlank(fileOrUrl)
      Q("")
    else if _s.startsWith(fileOrUrl, 'http')
      http.read fileOrUrl
    else
      fs.exists(fileOrUrl).then (exists) ->
        if exists
          fs.read fileOrUrl, 'r'
        else
          Q.reject new Error("File does not exist: #{fileOrUrl}")
