require File.dirname(__FILE__) + '/disk'
require File.dirname(__FILE__) + '/fake_dir'

class FakeDisk < Disk

  def make_dir(disk,path)
    FakeDir.new(disk,path)
  end

end
