# frozen_string_literal: true
require 'spec_helper'

module Thredded
  describe ModeratePost, '.run!' do
    let(:moderator) { create(:user) }

    it "'moderating a post from a pending user changes the user's moderation state" do
      user = create(:user)
      post = create(:post, user: user)
      Thredded::ModeratePost.run!(post: post, moderation_state: :approved, moderator: moderator)
      expect(post).to be_approved
      user.thredded_user_detail.reload
      expect(user.thredded_user_detail).to be_approved
    end

    it "moderating first post of a topic changes the topic's moderation_state" do
      topic = create(:topic, with_posts: 1)
      Thredded::ModeratePost.run!(post: topic.first_post, moderation_state: :approved, moderator: moderator)
      expect(topic.first_post).to be_approved
      topic.reload
      expect(topic).to be_approved
    end

    it 'blocking first post of a topic blocks all the other posts in the topic by the same user' do
      topic = create(:topic, with_posts: 1)
      another_post = create(:post, postable: topic, user: topic.user)
      Thredded::ModeratePost.run!(post: topic.first_post, moderation_state: :blocked, moderator: moderator)
      expect(topic.first_post).to be_blocked
      another_post.reload
      expect(another_post).to be_blocked
      topic.reload
      expect(topic).to be_blocked
    end

    it 'moderating does not change updated_at timestamp' do
      topic = create(:topic, with_posts: 1)
      expect { Thredded::ModeratePost.run!(post: topic.first_post, moderation_state: :blocked, moderator: moderator) }
        .to_not change { topic.first_post.reload.updated_at }
    end

    context 'when not Thredded.content_visible_while_pending_moderation' do
      around do |example|
        with_thredded_setting(:content_visible_while_pending_moderation, false, &example)
      end

      it 'notifies followers on approval' do
        # Create a topic and an additional post in that topic by another user.
        # Nobody should get notified as the posts are approved yet.
        topic = post = nil
        expect do
          topic = create(:topic, with_posts: 1)
          post = create(:post, postable: topic, user: create(:user))
        end.to_not change { UserPostNotification.count }

        # Approving the original topic should notify the follower who is not the topic creator.
        expect do
          Thredded::ModeratePost.run!(post: topic.first_post, moderation_state: :approved, moderator: moderator)
        end.to change { UserPostNotification.count }.by(1)

        # Approving the additional post in the topic should notify the topic creator.
        expect do
          Thredded::ModeratePost.run!(post: post, moderation_state: :approved, moderator: moderator)
        end.to change { UserPostNotification.count }.by(1)
      end
    end
  end
end
