require 'state_machine'

# Adds a generic implementation for sending messages between users
module HasMessages
  module MacroMethods
    # Creates the following message associations:
    # * +messages+ - Messages that were composed and are visible to the owner.
    #   Mesages may have been sent or unsent.
    # * +received_messages - Messages that have been received from others and
    #   are visible.  Messages may have been read or unread.
    # 
    # == Creating new messages
    # 
    # To create a new message, the +messages+ association should be used,
    # for example:
    # 
    #   user = User.find(123)
    #   message = user.messages.build
    #   message.subject = 'Hello'
    #   message.body = 'How are you?'
    #   message.to User.find(456)
    #   message.save
    #   message.deliver
    # 
    # == Drafts
    # 
    # You can get the drafts for a particular user by using the +unsent_messages+
    # helper method.  This will find all messages in the "unsent" state.  For example,
    # 
    #   user = User.find(123)
    #   user.unsent_messages
    # 
    # You can also get at the messages that *have* been sent, using the +sent_messages+
    # helper method.  For example,
    # 
    #  user = User.find(123)
    #  user.sent_messages
    def has_messages
      has_many  :messages,
                  :as => :sender,
                  :class_name => 'Message',
                  :conditions => {:hidden_at => nil},
                  :order => 'messages.created_at DESC'
      has_many  :received_messages,
                  :as => :receiver,
                  :class_name => 'MessageRecipient',
                  :include => :message,
                  :conditions => ['message_recipients.hidden_at IS NULL and messages.state = ?', 'sent'],
                  :order => 'messages.created_at DESC'
      #Unlabeled means message_recipients.label column is null, as opposed to 'spam' or 'archived'
      has_many  :unlabeled_messages,
                  :as => :receiver,
                  :class_name => 'MessageRecipient',
                  :include => :message,
                  :conditions => ['message_recipients.hidden_at IS NULL AND message_recipients.label IS NULL and messages.state = ?', 'sent'],
                  :order => 'messages.created_at DESC'
      #Labeled means message_recipients.label column is not null, i.e. the value is 'spam' or 'archived'
      has_many  :labeled_messages,
                  :as => :receiver,
                  :class_name => 'MessageRecipient',
                  :include => :message,
                  :conditions => ['message_recipients.hidden_at IS NULL AND message_recipients.label IS NOT NULL and messages.state = ?', 'sent'],
                  :order => 'messages.created_at DESC'

#      has_many  :received_message_threads,
#                  :as => :receiver,
#                  :class_name => 'MessageRecipient',
#                  :include => :message,
#                  :conditions => ['message_recipients.hidden_at IS NULL AND messages.state = ? and messages.original_message_id IS NOT NULL', 'sent'],
#                  :group => 'messages.original_message_id',
#                  :order => 'messages.created_at DESC'

      include HasMessages::InstanceMethods
    end
  end
  
  module InstanceMethods
    # Composed messages that have not yet been sent.  These consists of all
    # messages that are currently in the "unsent" state.
    def unsent_messages
      messages.with_state(:unsent)
    end
    
    # Composed messages that have already been sent.  These consists of all
    # messages that are currently in the "queued" or "sent" states.
    def sent_messages
      messages.with_states(:queued, :sent)
    end

    # Returns the most recent, unlabeled message of each thread.  
    def last_message_per_thread
      unlabeled_messages.group('COALESCE(original_message_id, messages.id)')
    end

    # Returns the most recent UNREAD and unlabeled message of each thread
    def last_unread_message_per_thread
      unlabeled_messages.with_state(:unread).group('COALESCE(original_message_id, messages.id)')
    end

    # Returns the most recent sent and unlabeled message for each thread
    def last_sent_message_per_thread
      unlabeled_messages.where(["messages.sender_id = ?",id]).group('COALESCE(original_message_id, messages.id)')
    end

    def last_archived_message_per_thread
      labeled_messages.with_label(:archived).group('COALESCE(original_message_id, messages.id)')
    end

    def show_thread(mr_id, filter)
      if (filter == 'archived' || filter == 'spam')
        # returns only the message_recipient records having the label matching filter's value, for the thread containing the message_recipient record referenced by mr_id
        mr = received_messages.where('message_recipients.id = ?',mr_id).first()
        return [] if mr.nil?
        original_message_id = mr.message.original_message_id.nil? ? mr.message.id : mr.message.original_message_id
        return labeled_messages.with_label(filter.to_sym).where("messages.id = ? or messages.original_message_id = ?", original_message_id, original_message_id)
      else 
        # returns only the message_recipient records without any label for the thread containing the message_recipient record referenced by mr_id
        mr = received_messages.where('message_recipients.id = ?',mr_id).first()
        return [] if mr.nil?
        original_message_id = mr.message.original_message_id.nil? ? mr.message.id : mr.message.original_message_id
        return unlabeled_messages.where("messages.id = ? or messages.original_message_id = ?", original_message_id, original_message_id)
      end

    end

  end
end

ActiveRecord::Base.class_eval do
  extend HasMessages::MacroMethods
end

