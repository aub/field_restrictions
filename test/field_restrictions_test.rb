require File.join(File.dirname(__FILE__), 'test_helper')

class Publication < ActiveRecord::Base
  has_many :articles
  has_many :images, :through => :articles
end

class Article < ActiveRecord::Base
  has_many :images
  belongs_to :publication
  
  restrict :images, :from => 'BadGuy'
end

class SubArticle < Article
  
end

class Image < ActiveRecord::Base
  belongs_to :article
  
  restrict :size, :from => 'BadGuy'
  restrict [:format, :mime_type], :to => ['Superhero', 'NiceGuy']
end

class FieldRestrictionsTest < Test::Unit::TestCase
  fixtures :all
  
  def setup
    @user = mock
    @user.stubs(:roles_for).returns(['BadGuy'])
    @image = Image.as(@user).find(:first)
    @article = Article.as(@user).find_by_title('all about degas')
  end
  
  def test_should_throw_exception_when_updating_restricted_fields_through_update_attributes
    assert_raise RestrictedAttributeError do
      @image.update_attributes(:size => '2')
    end
    assert_raise RestrictedAttributeError do
      @image.update_attributes(:mime_type => 'image/png')
    end
  end
  
  def test_should_not_throw_exception_when_editing_unrestricted_attributes
    assert_nothing_raised do
      @image.update_attributes(:title => 'woo')
    end
  end
  
  def test_should_not_throw_exception_when_the_user_has_the_correct_permissions
    @user.stubs(:roles_for).returns(['NiceGuy'])
    assert_nothing_raised do
      @image.update_attributes(:format => 'jpeg')
    end
  end
  
  def test_should_throw_exception_when_updating_a_single_attribute
    assert_raise RestrictedAttributeError do
      @image.update_attribute(:format, 'ack')
    end
  end
  
  def test_should_throw_exception_when_updating_a_single_attribute_through_attribute_equals
    assert_raise RestrictedAttributeError do
      @image.format = 'hack'
    end
  end
  
  def test_should_throw_exception_when_trying_to_set_a_restricted_association_proxy
    assert_raise RestrictedAttributeError do
      @article.images = []
    end
  end
  
  def test_should_throw_exception_when_using_create_on_a_restricted_association_proxy
    assert_raise RestrictedAttributeError do
      @article.images.create
    end
  end

  def test_should_throw_exception_when_using_new_on_a_restricted_association_proxy
    assert_raise RestrictedAttributeError do
      @article.images.create
    end
  end

  def test_should_throw_exception_when_using_build_on_a_restricted_association_proxy
    assert_raise RestrictedAttributeError do
      @article.images.create
    end
  end
  
  def test_should_allow_creation_through_the_association_proxy_when_unrestricted
    assert_nothing_raised do
      Publication.find(:first).articles.build
    end
  end
  
  def test_should_restrict_models_that_come_from_association_proxies
    assert_raise RestrictedAttributeError do
      @article.images.first.size = 12
    end
  end
  
  def test_should_restrict_parameters_through_subclasses
    @sub_article = SubArticle.as(@user).find_by_title('all about degas')
    assert_raise RestrictedAttributeError do
      @sub_article.update_attribute(:images, [])
    end
  end
  
  def test_should_throw_an_exception_when_trying_to_push_items_onto_an_association_proxy
    assert_raise RestrictedAttributeError do
      @article.images << Image.new
    end    
  end
  
  def test_shold_fail_to_assign_objects_through_the_association_proxy
    assert_raise RestrictedAttributeError do
      @article.images = []
    end
  end
  
  def test_should_restrict_setting_a_restricted_association_proxy_through_ids
    assert_raise RestrictedAttributeError do
      @article.image_ids = Image.find(:all).collect { |i| i.id }
    end
  end
  
  def test_should_restrict_properly_across_has_many_through
    assert_raise RestrictedAttributeError do
      Publication.as(@user).find_by_title('New York Times').images.first.format = 'noooo'
    end
  end
  
  def test_should_create_restricted_models_through_class_create
    assert_raise RestrictedAttributeError do
      Image.as(@user).create(:size => 122)
    end
  end

  def test_should_create_restricted_models_through_class_new
    assert_raise RestrictedAttributeError do
      Image.as(@user).new(:size => 122)
    end
  end
  
  def test_if_permitted
    a = Article.find(:first)
    test = 12
    a.if_permitted(@user, :images) do
      test = 13
    end
    assert_equal 12, test
  end
  
  def test_if_permitted_executed_block_when_permitted
    a = Article.find(:first)
    test = 12
    a.if_permitted(@user, :title) do
      test = 24
    end
    assert_equal 24, test
  end
  
  def test_if_permitted_executes_block_when_field_not_restricted
    a = Article.find(:first)
    test = 12
    a.if_permitted(@user, :hack) do
      test = 24
    end
    assert_equal 24, test    
  end
end
