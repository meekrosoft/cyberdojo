
# See comments at end of file

class HostDiskKatas
  include Enumerable

  def initialize(dojo)
    @dojo = dojo
    @path = slashed(config['root']['katas'])
  end

  def parent
    @dojo
  end

  # - - - - - - - - - - - - - - - - - - - - - - - -
  # Katas
  # - - - - - - - - - - - - - - - - - - - - - - - -

  def create_manifest(language, exercise, id = unique_id, now = time_now)
    # a kata's id has 10 hex chars. This gives 16^10 possibilities
    # which is 1,099,511,627,776 which is big enough to not
    # need to check that a kata with the id already exists.
    manifest = {
                       id: id,
                  created: now,
                 language: language.name,
                 exercise: exercise.name,
      unit_test_framework: language.unit_test_framework,
                 tab_size: language.tab_size
    }
    manifest[:visible_files] = language.visible_files
    manifest[:visible_files]['output'] = ''
    manifest[:visible_files]['instructions'] = exercise.instructions
    manifest
  end

  def create_kata(language, exercise, id = unique_id, now = time_now)
    manifest = create_manifest(language, exercise, id, now)
    create_kata_from_manifest(manifest)
  end

  def create_kata_from_manifest(manifest)
    kata = Kata.new(self, manifest[:id])
    make_dir(kata)
    dir(kata).write_json(manifest_filename, manifest)
    kata
  end

  def complete(id)
    # If at least 6 characters of the id are provided attempt to complete
    # it into the full 10 character id. Doing completion with fewer characters
    # would likely result in a lot of disk activity and no unique outcome.
    if !id.nil? && id.length >= 6
      # outer-dir has 2-characters
      outer_dir = disk[@path + outer(id)]
      if outer_dir.exists?
        # inner-dir has 8-characters
        dirs = outer_dir.each_dir.select { |inner_dir| inner_dir.start_with?(inner(id)) }
        id = outer(id) + dirs[0] if dirs.length == 1
      end
    end
    id || ''
  end

  def each
    return enum_for(:each) unless block_given?
    disk[@path].each_dir do |outer_dir|
      disk[@path + outer_dir].each_dir do |inner_dir|
        yield  Kata.new(self, outer_dir + inner_dir)
      end
    end
  end

  # - - - - - - - - - - - - - - - - - - - - - - - -
  # Kata
  # - - - - - - - - - - - - - - - - - - - - - - - -

  def [](id)
    return nil if !valid?(id)
    kata = Kata.new(self, id)
    kata_exists?(kata) ? kata : nil
  end

  def kata_exists?(kata) # TODO: private?
    dir(kata).exists?
  end

  def kata_manifest(kata)
    dir(kata).read_json(manifest_filename)
  end

  def kata_started_avatars(kata)
    lines, _ = shell.cd_exec(path(kata), 'ls -F | grep / | tr -d /')
    lines.split("\n") & Avatars.names
  end

  def kata_start_avatar(kata, avatar_names = Avatars.names.shuffle)
    avatar_name = avatar_names.detect do |name|
      _, exit_status = shell.cd_exec(path(kata), "mkdir #{name} #{stderr_2_stdout}")
      exit_status == shell.success
    end

    return nil if avatar_name.nil? # full!

    avatar = Avatar.new(kata, avatar_name)

    user_name = avatar.name + '_' + kata.id
    user_email = avatar.name + '@cyber-dojo.org'
    git.setup(path(avatar), user_name, user_email)

    write_avatar_manifest(avatar, kata.visible_files)
    git.add(path(avatar), manifest_filename)

    write_avatar_increments(avatar, [])
    git.add(path(avatar), increments_filename)

    sandbox = Sandbox.new(avatar)
    make_dir(sandbox)
    avatar.visible_files.each do |filename, content|
      write(sandbox, filename, content)
      git.add(path(sandbox), filename)
    end

    git.commit(path(avatar), tag=0)

    avatar_name
  end

  # - - - - - - - - - - - - - - - - - - - - - - - -
  # Avatar
  # - - - - - - - - - - - - - - - - - - - - - - - -

  def avatar_exists?(avatar)
    dir(avatar).exists?
  end

  def avatar_increments(avatar)
    # implicitly for current tag
    dir(avatar).read_json(increments_filename)
  end

  def avatar_visible_files(avatar)
    # implicitly for current tag
    dir(avatar).read_json(manifest_filename)
  end

  def avatar_ran_tests(avatar, delta, files, now, output, colour)
    # update manifest
    write(avatar.sandbox, 'output', output)
    files['output'] = output
    write_avatar_manifest(avatar, files)
    # update Red/Amber/Green increments
    rags = avatar_increments(avatar)
    tag = rags.length + 1
    rags << { 'colour' => colour, 'time' => now, 'number' => tag }
    write_avatar_increments(avatar, rags)
    # git-commit the manifest, increments, and visible-files
    git.commit(path(avatar), tag)
    rags
  end

  # - - - - - - - - - - - - - - - - - - - - - - - -
  # Tag
  # - - - - - - - - - - - - - - - - - - - - - - - -

  def tag_visible_files(avatar, tag)
    # retrieve all the files in one go
    JSON.parse(git.show(path(avatar), "#{tag}:#{manifest_filename}"))
  end

  def tag_git_diff(avatar, was_tag, now_tag)
    git.diff(path(avatar), was_tag, now_tag)
  end

  # - - - - - - - - - - - - - - - - - - - - - - - -
  # Path
  # - - - - - - - - - - - - - - - - - - - - - - - -

  def path(obj)
    case obj.class.name
    when 'Sandbox' then path(obj.parent) + 'sandbox' + '/'
    when 'Avatar'  then path(obj.parent) + obj.name + '/'
    when 'Kata'    then path(obj.parent) + outer(obj.id) + '/' + inner(obj.id) + '/'
    when self.class.name then @path
    end
  end

  def write(sandbox, filename, content)
    dir(sandbox).write(filename, content)
  end

  private

  include ExternalParentChainer
  include IdSplitter
  include TimeNow
  include UniqueId
  include Slashed

  def valid?(id)
    id.class.name == 'String' &&
      id.length == 10 &&
        id.chars.all? { |char| hex?(char) }
  end

  def hex?(char)
    '0123456789ABCDEF'.include?(char)
  end

  def make_dir(obj)
    dir(obj).make
  end

  def dir(obj)
    disk[path(obj)]
  end

  def write_avatar_manifest(avatar, files)
    dir(avatar).write_json(manifest_filename, files)
  end

  def write_avatar_increments(avatar, increments)
    dir(avatar).write_json(increments_filename, increments)
  end

  def increments_filename
    # Each avatar's increments stores a cache of colours and time-stamps
    # for all the avatar's [test]s. Helps optimize traffic-lights views.
    'increments.json'
  end

  def manifest_filename
    # Each kata's manifest stores the kata's meta information
    # such as the chosen language, tests, exercise.
    # Each avatar's manifest stores a cache of the avatar's
    # current visible files [filenames and contents].
    'manifest.json'
  end

  def stderr_2_stdout
    '2>&1'
  end

end

# - - - - - - - - - - - - - - - - - - - - - - - -
# There are three main moving parts in cyber-dojo:
#
# 1. READ
#    the [languages,exercises,caches] folders which are
#    local to the cyber-dojo server and read-only.
#
# 2. EXECUTE
#    the runners which produce an output file from a set
#    of source files and a language's image_name. This
#    output is regex'd to get its Red/Amber/Green colour.
#
# 3. WRITE
#    the files+output from each [test] event are saved as
#    a tag in a git repo associated with the kata+avatar.
#    There are also writes associated with creating each
#    kata and starting each each avatar.
#
# - - - - - - - - - - - - - - - - - - - - - - - -
# This class's methods holds all the reads/writes for 3.
# Currently it uses the cyber-dojo server's file-system [katas]
# folder using the same HostDisk object as 1 but this needs
# decoupling (see avatar_run_tests comments below).
# In fact, this is *an* implementation of katas.
# Its HostDiskKatas.
#
# Viz, this class represents the API needed on its own
# dedicated web server.
# - - - - - - - - - - - - - - - - - - - - - - - -


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# kata_start_avatar(kata, avatar_names)
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Starting an avatar needs to be atomic otherwise two
# laptops in a cyber-dojo could start as the same animal.
#
#   app/models/kata.rb    start_avatar()
#   app/models/avatars.rb started_avatars()
#
# On a non NFS POSIX file system I do this relying on
# mkdir being atomic.
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# avatar_run_tests(avatar, delta, files, now, max_seconds)
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Currently works by saving the files to the file-system (in the avatar's
# sandbox) and *then* the runner makes use of these saved files
# (eg docker-runner's .sh file volume-mounts the sandbox).
#
# I plan to reverse this ordering and decouple the runners from the
# persistence strategy (the file-system + git). Namely...
#
# 1. Don't save the files to the file-system; let the runner decide what to
#    do. Maybe runner is hosted inside a web-server which receives the files,
#    saves them to a ram disk folder, which a docker image then volume-mounts.
#    Perhaps there are several such such servers for scalability. This also
#    suggests the the browser sending the files *directly* to such a web-server
#    rather than to the cyber-dojo server (which in turn sends them on to the
#    web-server).
#
# 2. Once the runner has finished, the output file is added to the files
#    sent from browser and persisted in one go (rather than two steps; one
#    for saving all the files except the output, another for saving just the
#    output).
#
# Note
# Step 2 can be executed as a background fire-and-forget task.
# The browser only needs the results of step 1.
# The rails view-code currently redraws *all* the traffic-lights
# but that needs refactoring.
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -


