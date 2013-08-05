
# Handler for drag events is needed, otherwise the drop event does not work.
onDragOver = (e) ->
  e.stopPropagation()
  e.preventDefault()

# Handler for when a file is dropped on the drop zone.
onDrop = (e) ->
  e.stopPropagation()
  e.preventDefault()
  
  # Testing read performance on NGC_6946_NA_CUBE_THINGS.FITS
  # I chose this file because it's sufficiently large, yet still within the memory
  # scope of what Chrome (as a 32 bit app) can handle.
  file = e.dataTransfer.files[0]
  
  # These byte offsets are hard coded to the stream of bytes representing the 3D image.
  startByte = 54720
  endByte = startByte + 482344960
  
  # The cube is stored as Float32, so take the byte length (482344960 - 54720) / 4
  nElements = 120586240
  
  # Get the blob representing only the data cube.
  # At this point we're still working with only a reference to the file.  No I/O has occurred.
  blob = file.slice(startByte, endByte)
  
  # Read the blob using 4 Web Workers
  readBinary(blob, 4)


readBinary = (blob) ->
  startTime = new Date()
  
  # Create storage for blob
  nElements = blob.size / 4
  arr = new Float32Array(nElements)
  
  reader = new FileReader()
  reader.onloadstart = (e) ->
    console.log 'onloadstart'
  reader.onload = (e) ->
    console.log 'onload'
  reader.onloadend = (e) ->
    buffer = e.target.result
    arr.set(new Float32Array(buffer), 0)
    
    endTime = new Date()
    document.querySelector('.timer').textContent = "duration: #{endTime - startTime}"
  
  reader.readAsArrayBuffer(blob)
  

readBinary1 = (blob, nWorkers) ->
  
  # Start a rudimentary timer
  startTime = new Date()
  
  # Set 16 MB as chuck size to read file
  chunkSize = 16777216
  
  # Get the byte size of the blob
  blobSize = blob.size
  
  # Get the number of 16 mb chunks
  nChunks = i = Math.ceil(blobSize / chunkSize)
  
  # Create slices from entire blob
  blobs = []
  while i--
    startByte = i * chunkSize
    
    obj =
      startByte: startByte
      slice: blob.slice(startByte, startByte + chunkSize)
    blobs.push obj
  
  #
  # Split the blob slices into subarrays
  #
  
  # Create storage for subarrays
  blobArrays = []
  
  # Determine the base number of blobs per array and the remainder
  blobsPerArray = ~~(nChunks / nWorkers)
  blobRemainder = nChunks % blobsPerArray
  
  # Populate subarrays evenly
  while blobs.length > blobRemainder
    blobArrays.push blobs.splice(0, blobsPerArray)
  
  # Distribute remaining slices equally
  i = 0
  while blobRemainder--
    blobArrays[i].push blobs.splice(0, 1)[0]
    i += 1
  
  # Initialize array that will store the entire blob
  arr = new Float32Array(blobSize / 4)
  
  # Define inline worker function
  onmessage = (e) ->
    
    obj = e.data
    
    # Use the synchronous file reader to read binary data
    reader = new FileReaderSync()
    buffer = reader.readAsArrayBuffer(obj.slice)
    
    # # Send message to main thread for when blob is in memory
    # postMessage("inMemory")
    
    # Initialize typed array
    arr = new Uint32Array(buffer)
    
    # Swap endian
    i = arr.length
    while i--
      value = arr[i]
      arr[i] = ((value & 0xFF) << 24) | ((value & 0xFF00) << 8) | ((value >> 8) & 0xFF00) | ((value >> 24) & 0xFF)
    
    # Get updated buffer
    buffer = arr.buffer
    
    # Post using transferable objects
    # NOTE: Why does this not work with typed arrays?!?!
    postMessage({startByte: obj.startByte, buffer}, [buffer])
  
  # Trick to format function for worker when using CoffeeScript
  fn = onmessage.toString().replace('return postMessage', 'self.postMessage')
  fn = "onmessage = #{fn}"
  
  # Create URL for onmessage function used by worker
  onMessageBlob = new Blob([fn], {type: "application/javascript"})
  onMessageUrl = URL.createObjectURL(onMessageBlob)
  
  # Storage for returned buffer
  bufferArrays = []
  
  # Create workers
  workers = {}
  while nWorkers--
    
    worker = new Worker(onMessageUrl)
    worker.index = nWorkers
    
    # Define callback for when job is complete
    worker.onmessage = (e) ->
      data = e.data
      startByte = data.startByte
      
      # Append data to buffer array
      bufferArrays[@index].push data
      # # Reconstruct entire array
      # arr.set(new Float32Array(data.buffer), startByte / 4)
      
      blobs = blobArrays[@index]
      b = blobs.shift()
      if b?
        @postMessage(b)
      else
        
        # No more slices to process for this worker
        
        # Delete worker from object of workers
        delete workers[@index]
        
        # Check number of remaining workers
        nRemainingWorkers = Object.keys(workers).length
        
        if nRemainingWorkers is 0
          
          # Reading is now complete
          endTime = new Date()
          time = endTime - startTime
          
          # Print time to DOM
          docFrag = document.createDocumentFragment()
          p = document.createElement('p')
          p.textContent = time
          docFrag.appendChild(p)
          document.body.appendChild(docFrag)
          
          # Recontruct array
          for buffers in bufferArrays
            for obj in buffers
              arr.set(new Float32Array(obj.buffer), obj.startByte / 4)
          
          # Log a subarray because logging the entire array is memory intensive.  The JS
          # console is a memory hog.
          console.log arr.subarray(12345, 12345 + 10)
        
        # Terminate worker
        @terminate()
    
    bufferArrays[nWorkers] = []
    workers[nWorkers] = worker
  
  # Start each worker
  for index, worker of workers
    blobs = blobArrays[worker.index]
    b = blobs.shift()
    worker.postMessage(b)


domReady = ->
  drop = document.querySelector('.drop')
  drop.addEventListener('dragover', onDragOver, false)
  drop.addEventListener('drop', onDrop, false)

# Wait until the DOM is ready
window.addEventListener('DOMContentLoaded', domReady, false)