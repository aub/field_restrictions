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
    @image.update_attributes(:size => '2')
    assert !@image.valid?
    assert @image.errors.on(:size)
    
    @image.update_attributes(:mime_type => 'image/png')
    assert !@image.valid?
    assert @image.errors.on(:mime_type)
  end
  
  def test_should_not_throw_exception_when_editing_unrestricted_attributes
    @image.update_attributes(:title => 'woo')
    assert @image.valid?
    assert_nil @image.errors.on(:title)
  end
  
  def test_should_not_throw_exception_when_the_user_has_the_correct_permissions
    @user.stubs(:roles_for).returns(['NiceGuy'])
    @image.update_attributes(:format => 'jpeg')
    assert @image.valid?
    assert_nil @image.errors.on(:format)
  end
  
  def test_should_throw_exception_when_updating_a_single_attribute
    @image.update_attribute(:format, 'ack')
    assert !@image.valid?
    assert @image.errors.on(:format)
  end
  
  def test_should_throw_exception_when_updating_a_single_attribute_through_attribute_equals
    @image.format = 'hack'
    assert !@image.valid?
    assert @image.errors.on(:format)
  end
  
  def test_should_throw_exception_when_trying_to_set_a_restricted_association_proxy
    @article.images = []
    assert !@article.valid?
    assert @article.errors.on(:images)
  end
  
  def test_should_throw_exception_when_using_create_on_a_restricted_association_proxy
    @article.images.create
    assert !@article.valid?
    assert @article.errors.on(:images)
  end

  def test_should_throw_exception_when_using_new_on_a_restricted_association_proxy
    @article.images.new
    assert !@article.valid?
    assert @article.errors.on(:images)
  end

  def test_should_throw_exception_when_using_build_on_a_restricted_association_proxy
    @article.images.build
    assert !@article.valid?
    assert @article.errors.on(:images)
  end
  
  def test_should_allow_creation_through_the_association_proxy_when_unrestricted
    p = Publication.find(:first)
    p.articles.build
    assert p.valid?
    assert_nil p.errors.on(:articles)
  end
  
  def test_should_allow_build_for_multiple_objects
    @article.images.each { |image| image.destroy }
    @article.images.build([{:title => 'a'}, {:title => 'b'}])
    @article.reload
    assert_equal 2, @article.images.size
    assert_equal %w(a b), @article.images.map { |i| i.title }.sort
  end
  
  def test_should_restrict_models_that_come_from_association_proxies_with_first
    i = @article.images.first
    i.size = 12
    assert !i.valid?
    assert i.errors.on(:size)
  end

  def test_should_restrict_models_that_come_from_association_proxies_with_last
    i = @article.images.last
    i.size = 12
    assert !i.valid?
    assert i.errors.on(:size)
  end

  def test_should_restrict_models_that_come_from_association_proxies_with_all
    images = @article.images.all
    images.each do |i|
      i.size = 12
      assert !i.valid?
      assert i.errors.on(:size)
    end
  end

  def test_should_restrict_models_that_come_from_association_proxies_with_find
    image = @article.images.find_by_title('picasso')
    image.size = 12
    assert !image.valid?
    assert image.errors.on(:size)
  end
  
  def test_should_not_restrict_calls_to_all_on_association_proxies
    @article.images.all
    assert @article.valid?
    assert_nil @article.errors.on(:images)
  end
  
  def test_should_restrict_parameters_through_subclasses
    @sub_article = SubArticle.as(@user).find_by_title('all about degas')
    @sub_article.update_attribute(:images, [])
    assert !@sub_article.valid?
    assert @sub_article.errors.on(:images)
  end
  
  def test_should_throw_an_exception_when_trying_to_push_items_onto_an_association_proxy
    @article.images << Image.new
    assert !@article.valid?
    assert @article.errors.on(:images)
  end
  
  def test_shold_fail_to_assign_objects_through_the_association_proxy
    @article.images = []
    assert !@article.valid?
    assert @article.errors.on(:images)
  end
  
  def test_should_restrict_setting_a_restricted_association_proxy_through_ids
    @article.image_ids = Image.find(:all).collect { |i| i.id }
    assert !@article.valid?
    assert @article.errors.on(:images)
  end
  
  def test_should_restrict_properly_across_has_many_through
    p = Publication.as(@user).find_by_title('New York Times')
    p.images.first.format = 'noooo'
    assert !p.images.first.valid?
    assert p.images.first.errors.on(:format)
  end
  
  def test_should_create_restricted_models_through_class_create
    i = Image.as(@user).create(:size => 122)
    assert !i.valid?
    assert i.errors.on(:size)
  end

  def test_should_create_restricted_models_through_class_new
    i = Image.as(@user).new(:size => 122)
    assert !i.valid?
    assert i.errors.on(:size)
  end
  
  def test_if_permitted
    a = Article.find(:first)
    assert !a.permitted?(@user, :images)
  end
  
  def test_if_permitted_executed_block_when_permitted
    a = Article.find(:first)
    assert a.permitted?(@user, :title)
  end
  
  def test_if_permitted_executes_block_when_field_not_restricted
    a = Article.find(:first)
    assert a.permitted?(@user, :hack)
  end
  
  def test_if_permitted_takes_an_array_of_attributes_to_be_ored_together
    i = Image.find(:first)
    assert i.permitted?(@user, [:hack1, :mime_type], :or)
    assert !i.permitted?(@user, [:format, :mime_type])
  end
  
  def test_if_permitted_can_take_a_logical_operator
    i = Image.find(:first)
    assert i.permitted?(@user, [:hack1, :hack2], :and)
    assert !i.permitted?(@user, [:hack1, :mime_type], :and)
    assert i.permitted?(@user, [:hack1, :mime_type], :or)
    assert !i.permitted?(@user, [:format, :mime_type], :or)
  end
end
